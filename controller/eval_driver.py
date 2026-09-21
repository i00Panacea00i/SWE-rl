#!/usr/bin/env python3
"""独立 vLLM 评估 driver —— 绕开 verl 的 FSDP/actor 显存栈。

背景：verl 共卡架构（FSDP actor + ref + vLLM colocate）在评估路径的初始权重同步
（update_weights → vLLM 权重唤醒）会把单卡显存打到 44.2/44.39GB，差 192MB 即 OOM
（训练路径因分配模式不同可过）。本 driver 改为「vLLM 独占显存纯推理 + 复用项目沙箱/
判分组件」，从根上消除该冲突。

复用（与训练同源，保证公平性与轨迹同构）：
  - sandbox.harness.load_instances / episode.EpisodeSession / evaluate_patch
  - sandbox.action_protocol.parse_action / bounded_observation

生成模式：**同步轮次推进**——每轮对所有活跃题批量生成（vLLM 满批处理），
沙箱执行用线程池并发。跨题互不干扰，且与训练 AgentLoop 的逐轮语义一致。

用法:
  python controller/eval_driver.py --parquet <heldout.parquet> --out <dir> \
    --model /mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct \
    --variant base|lora [--lora-path <hf-adapter>] [--n 1] [--temperature 0.0] \
    [--max-steps 12] [--action-tokens 2048] [--workers 10] [--limit N]
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import pandas as pd
from vllm import LLM, SamplingParams
from vllm.lora.request import LoRARequest

from sandbox.action_protocol import bounded_observation, parse_action
from sandbox.episode import EpisodeSession, evaluate_patch
from sandbox.harness import load_instances


def log(msg: str):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--parquet", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--variant", choices=["base", "lora"], required=True)
    ap.add_argument("--lora-path", default="")
    ap.add_argument("--n", type=int, default=1)
    ap.add_argument("--sample-offset", type=int, default=0,
                    help="采样编号起始（AGS 沙箱配额 100 → 分批采样时避免目录冲突）")
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--max-steps", type=int, default=12)
    ap.add_argument("--action-tokens", type=int, default=2048)
    ap.add_argument("--observation-tokens", type=int, default=512)
    ap.add_argument("--sandbox-timeout", type=int, default=1800)
    ap.add_argument("--cmd-timeout", type=int, default=120)
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    if args.variant == "lora" and not args.lora_path:
        raise SystemExit("variant=lora 需要 --lora-path")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_parquet(args.parquet)
    if args.limit:
        df = df.head(args.limit)
    prompts: dict[str, list[dict]] = {}
    order: list[str] = []
    for _, row in df.iterrows():
        iid = row["extra_info"]["instance_id"]
        order.append(iid)
        prompts[iid] = [dict(m) for m in row["prompt"]]
    # 每题 n 次采样 → 任务列表（sample_offset 支持分批采样，目录名 s<k> 不冲突）
    jobs = [(iid, k + args.sample_offset) for iid in order for k in range(args.n)]
    log(f"评估集 {len(order)} 题 × n={args.n}（temp={args.temperature}）= {len(jobs)} 条轨迹")

    insts = {i.instance_id: i for i in load_instances()}
    missing = [i for i in order if i not in insts]
    if missing:
        raise SystemExit(f"instances.jsonl 缺少: {missing}")

    # ── vLLM（独占显存纯推理：权重 15.3GB/卡 + KV 充裕，无 actor/FSDP 冲突）──
    log(f"加载模型 {args.model}（TP=4, lora={args.variant == 'lora'}）…")
    llm = LLM(model=args.model, tensor_parallel_size=4, dtype="bfloat16",
              max_model_len=16384, gpu_memory_utilization=0.85,
              enable_lora=args.variant == "lora", max_lora_rank=32,
              enforce_eager=True, disable_log_stats=True)
    tok = llm.get_tokenizer()
    lora_req = LoRARequest("swe-eval", 1, args.lora_path) if args.variant == "lora" else None
    sp = SamplingParams(temperature=args.temperature, max_tokens=args.action_tokens)
    log("模型就绪")

    # ── 沙箱并发启动 ──
    states: list[dict] = []
    lock_dir = time.time()

    def init_one(iid: str, k: int) -> dict:
        inst = insts[iid]
        d = out_dir / f"{iid}__s{k}"
        d.mkdir(parents=True, exist_ok=True)
        sess = EpisodeSession(inst, d, timeout=args.sandbox_timeout,
                              apply_test_patch=True)
        sess.start()
        return {"iid": iid, "k": k, "inst": inst, "sess": sess, "dir": d,
                "messages": [dict(m) for m in prompts[iid]],
                "turn": 0, "done": False, "error": None}
    log("并发创建沙箱…")
    failed_jobs: list[dict] = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(init_one, iid, k): (iid, k) for iid, k in jobs}
        for f in as_completed(futs):
            iid, k = futs[f]
            try:
                states.append(f.result())
            except Exception as e:  # noqa: BLE001
                failed_jobs.append({"iid": iid, "k": k, "error": str(e)[:200]})
                log(f"  ✗ 沙箱启动失败 {iid}__s{k}: {str(e)[:160]}")
    log(f"沙箱就绪 {len(states)}/{len(jobs)}")
    if failed_jobs:
        (out_dir / "failed_jobs.json").write_text(
            json.dumps(failed_jobs, ensure_ascii=False, indent=2))
        log(f"失败任务清单已写 {out_dir / 'failed_jobs.json'}（{len(failed_jobs)} 条）")

    # ── 同步轮次推进 ──
    MAXLEN = 16384
    for turn in range(1, args.max_steps + 1):
        active = [s for s in states if not s["done"]]
        if not active:
            break
        # ── 上下文预算管理（与训练 AgentLoop 一致：超限即终止该题）──
        LIMIT = MAXLEN - 512          # 预留 512 token 输出空间
        ready: list[dict] = []
        texts: list[str] = []
        for s in active:
            text = tok.apply_chat_template(s["messages"], tokenize=False,
                                           add_generation_prompt=True)
            n = len(tok.encode(text))
            if n > LIMIT:
                s["done"] = True
                s["turn"] = turn - 1
                s["messages"].append({"role": "user",
                                      "content": "Context budget exhausted; forced submission."})
                continue
            s["_prompt_tokens"] = n
            ready.append(s)
            texts.append(text)
        if not ready:
            break
        max_out = max(64, min(args.action_tokens, MAXLEN - max(s["_prompt_tokens"] for s in ready) - 8))
        sp_turn = SamplingParams(temperature=args.temperature, max_tokens=max_out)
        t0 = time.time()
        outs = llm.generate(texts, sp_turn, lora_request=lora_req)
        active = ready
        log(f"[轮次 {turn}] 生成 {len(active)} 条（{time.time() - t0:.0f}s, max_out={max_out}）")

        def exec_one(s: dict, out) -> None:
            action = out.outputs[0].text.strip()
            s["messages"].append({"role": "assistant", "content": action})
            s["turn"] = turn
            try:
                cmd, submit = parse_action(action)
            except Exception as e:  # noqa: BLE001
                s["messages"].append({"role": "user",
                                      "content": f"Action format error; no command executed: {e}"})
                return
            if submit:
                s["done"] = True
                s["messages"].append({"role": "user", "content": "Submission received."})
                return
            try:
                code, so, se = s["sess"].run(cmd, timeout=args.cmd_timeout)
                obs = f"exit_code={code}\n{so}{se}"
            except Exception as e:  # noqa: BLE001
                obs = f"Sandbox error: {str(e)[:200]}"
            s["messages"].append({"role": "user",
                                  "content": bounded_observation(tok, obs, args.observation_tokens)})

        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            list(ex.map(lambda p: exec_one(*p), zip(active, outs)))
        # 轮次耗尽标记
        for s in states:
            if not s["done"] and s["turn"] >= args.max_steps:
                s["done"] = True

    # ── 判分（全新沙箱，与训练判分同源）──
    log("判分中（每题独立沙箱）…")
    results: dict[str, dict] = {}

    def judge_one(s: dict) -> tuple[str, dict]:
        key = f"{s['iid']}__s{s['k']}"
        try:
            patch = s["sess"].export_patch()
            (s["dir"] / "candidate.patch").write_text(patch)
            s["sess"].close()
            res = evaluate_patch(s["inst"], patch, s["dir"], timeout=args.sandbox_timeout)
        except Exception as e:  # noqa: BLE001
            try:
                s["sess"].close()
            except Exception:  # noqa: BLE001
                pass
            res = {"reward": 0.0, "resolved": False, "error": str(e)[:300]}
        # 轨迹落盘（与训练轨迹同构：episode.json + candidate.patch + result.json）
        try:
            json.dump({"schema_version": 1, "run_id": s["dir"].parent.name,
                       "episode_id": key, "instance_id": s["iid"], "sample": s["k"],
                       "variant": args.variant, "turns": s["turn"],
                       "messages": s["messages"], "reward": res.get("reward"),
                       "resolved": res.get("resolved")},
                      open(s["dir"] / "episode.json", "w"), ensure_ascii=False)
        except Exception:  # noqa: BLE001
            pass
        return key, res

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(judge_one, s) for s in states]
        done = 0
        for f in as_completed(futs):
            key, res = f.result()
            results[key] = res
            done += 1
            log(f"  判分 {done}/{len(futs)}: {key} reward={res.get('reward')}")

    # ── 汇总 ──
    per_instance: dict[str, list[dict]] = {}
    for key, res in results.items():
        iid = key.rsplit("__s", 1)[0]
        per_instance.setdefault(iid, []).append(res)
    n_inst = len(per_instance)
    pass1 = sum(1 for rs in per_instance.values() if any(r.get("resolved") for r in rs))
    n_res = sum(len(rs) for rs in per_instance.values())
    res_res = sum(1 for rs in per_instance.values() for r in rs if r.get("resolved"))
    f2p_rates = [r["grade"]["f2p_passed"].__len__() /
                 max(1, len(r["grade"]["f2p_passed"]) + len(r["grade"]["f2p_failed"]))
                 for rs in per_instance.values() for r in rs if r.get("grade")]
    summary = {
        "variant": args.variant, "n": args.n, "temperature": args.temperature,
        "instances": n_inst, "instances_requested": len(order),
        "trajectories": n_res,
        # n=1 时 pass_at_1 为真实 pass@1；n>1 时 pass_at_n 为"至少 1 次成功"（pass@n）
        "pass_at_1": round(pass1 / max(1, n_inst), 4) if args.n == 1 else None,
        "pass_at_n": round(pass1 / max(1, n_inst), 4) if args.n > 1 else None,
        "resolved_rate_trajectory": round(res_res / max(1, n_res), 4),
        "f2p_rate_mean": round(sum(f2p_rates) / max(1, len(f2p_rates)), 4),
        "per_instance": {iid: {"resolved_any": any(r.get("resolved") for r in rs),
                               "resolved_count": sum(1 for r in rs if r.get("resolved")),
                               "rewards": [r.get("reward") for r in rs]}
                         for iid, rs in per_instance.items()},
    }
    json.dump(summary, open(out_dir / "summary.json", "w"),
              ensure_ascii=False, indent=2)
    metric_val = summary["pass_at_1"] if args.n == 1 else summary["pass_at_n"]
    metric_name = "pass@1" if args.n == 1 else f"pass@{args.n}"
    log(f"=== 完成 | {metric_name} = {metric_val} ({pass1}/{n_inst}) | "
        f"轨迹通过率 {summary['resolved_rate_trajectory']} | "
        f"f2p 均值 {summary['f2p_rate_mean']} ===")
    print(json.dumps({k: v for k, v in summary.items() if k != "per_instance"},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
