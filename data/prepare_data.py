"""instances.jsonl / benchmark.jsonl → verl 训练 parquet。

verl AgentLoop 标准格式：每行 {data_source, prompt(对话列表), ability,
reward_model{style:rule}, extra_info}。extra_info 携带沙箱路由信息
（tool_name/image_ags），AgentLoop 侧据此拉起对应沙箱。

默认剔除 flaky 实例（sympy__sympy-11384 在双向验证中不稳定，不可靠 reward）。

用法：
  venv/bin/python data/prepare_data.py \
      --input output/merged/benchmark.jsonl --output data/train.parquet
  venv/bin/python data/prepare_data.py --input data/instances.jsonl \
      --output data/train.parquet   # 无 validated 数据时直接用元数据（附 --no-flaky-filter 需显式）
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

# 训练/评估必须使用同一套系统提示（README 已知坑 #3）
SYSTEM_PROMPT = (
    "You are an autonomous software engineer resolving a real-world GitHub issue in the "
    "repository checked out at /testbed.\n"
    "Rules:\n"
    "- Output EXACTLY ONE bash command per turn. No explanations, no markdown, no commentary.\n"
    "- /testbed IS the repository root; the project package sits directly under it "
    "(/testbed/django, /testbed/sklearn, /testbed/astropy, ...). Never repeat the repository "
    "name twice in a path.\n"
    "- The failing target tests are ALREADY PRESENT in the sandbox. Run them first to see the "
    "exact failure, then fix the source code.\n"
    "- Edit files only with non-interactive tools (sed -i, python heredoc, patch). "
    "nano and vim are NOT installed.\n"
    "- Keep the edit MINIMAL: prefer one `sed -i` or a short `python -c` snippet. "
    "Do NOT paste whole files or long unified diffs.\n"
    "- Edit source code only. Never edit tests or build configuration: such patches are rejected.\n"
    "- The sandbox has no Internet access. Keep observations short with targeted commands.\n"
    "- Use at least three meaningful shell operations in separate turns: inspect the hinted "
    "source, edit it, and run the relevant tests. Never add documentation to fill turns.\n"
    "- When the fix is in place, output exactly: SUBMIT"
)

USER_TEMPLATE = (
    "You are working on the repository `{repo}` at commit {base_commit} "
    "(directory /testbed).\n\n"
    "GitHub issue:\n{problem}\n\n"
    "{hint}\n\n"
    "These tests currently fail and must pass:\n{f2p}\n\n"
    "Run them with:\n{test_command}\n\n"
    "Fix the source code so these tests pass, then output SUBMIT."
)


def _localization_hint(gold_patch: str) -> str:
    """定位提示：给出修复涉及的文件与变更所在函数/类。

    7B 基座在纯 issue 描述下完全定位不到改动点（探索 12 步后仍写不出匹配的编辑），
    导致执行奖励恒为 0、GRPO 无梯度。提供文件级定位（RL-for-SWE 常见做法）后，
    模型仍须自行写出正确修复，奖励口径不变。
    """
    files, regions = [], []
    for line in gold_patch.splitlines():
        if line.startswith("+++ b/"):
            files.append(line[len("+++ b/"):])
        elif line.startswith("@@") and line.count("@@") >= 2:
            tail = line.split("@@", 2)[-1].strip()
            if tail:
                regions.append(tail)
    files = list(dict.fromkeys(f for f in files if f != "/dev/null"))
    if not files:
        return ""
    out = ["Localization hint: the fix belongs in the following file(s):"]
    out += [f"- {f}" for f in files]
    return "\n".join(out)


def _test_command(eval_sh: str) -> str:
    """从官方 eval.sh 中提取测试命令（标记之间的部分），供 Agent 复现失败。"""
    lines = eval_sh.splitlines()
    starts = [i for i, line in enumerate(lines) if line == ": '>>>>> Start Test Output'"]
    ends = [i for i, line in enumerate(lines) if line == ": '>>>>> End Test Output'"]
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        return ""
    return "\n".join(lines[starts[0] + 1:ends[0]]).strip()

KNOWN_FLAKY = {"sympy__sympy-11384"}  # 双向验证确认不稳定（golden 通过率 ~50%）


def main():
    import hashlib
    import pandas as pd

    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="output/merged/benchmark.jsonl")
    ap.add_argument("--output", default="data/train.parquet")
    ap.add_argument("--max-steps-hint", type=int, default=12)
    ap.add_argument("--validation-dir")
    ap.add_argument("--allow-unvalidated", action="store_true", help="仅用于接入冒烟，不可计为验收")
    ap.add_argument("--eval-ids", help="保持已冻结的4道评估题，不随训练题替换而重新抽样")
    ap.add_argument("--split-dir", help="生成固定6训练/4评估划分，必须有10题")
    args = ap.parse_args()
    kit = Path(__file__).resolve().parent.parent
    inp = kit / args.input
    rows = [json.loads(l) for l in inp.read_text().splitlines() if l.strip()]
    excluded = KNOWN_FLAKY | {"pylint-dev__pylint-4551"}
    rows = sorted((r for r in rows if r["instance_id"] not in excluded), key=lambda r: r["instance_id"])
    if not rows or len({r["instance_id"] for r in rows}) != len(rows):
        ap.error("Empty or duplicate input instances")
    for r in rows:
        if args.validation_dir:
            report = json.loads((Path(args.validation_dir) / r["instance_id"] / "validation.json").read_text())
            status = report.get("status")
        else:
            status = r.get("validation", {}).get("status")
        if status != "validated" and not args.allow_unvalidated:
            ap.error(f"Instance is not validated: {r['instance_id']}")

    manifest = {"dataset": "princeton-nlp/SWE-bench", "source_split": "test",
                "split_rule": "sha256(round0-v1:instance_id), first4 eval, remaining6 train",
                "train": [], "eval": [], "instances": {},
                "system_prompt_sha256": hashlib.sha256(SYSTEM_PROMPT.encode()).hexdigest()}
    eval_ids = set()
    if args.split_dir:
        if len(rows) != 10:
            ap.error("The approved round requires exactly ten candidates")
        order = sorted((r["instance_id"] for r in rows),
                       key=lambda iid: hashlib.sha256(("round0-v1:" + iid).encode()).hexdigest())
        eval_ids = set(order[:4])
        if args.eval_ids:
            eval_ids = set(args.eval_ids.split(","))
            if len(eval_ids) != 4 or not eval_ids.issubset({r["instance_id"] for r in rows}):
                ap.error("Exactly four valid held-out instance IDs are required")
            manifest["split_rule"] = "Preserved pre-training held-out IDs; failed training image replaced"
    specs_dir = kit / "data/task_specs"
    out_rows = []
    for index, r in enumerate(rows):
        iid = r["instance_id"]
        tests = json.loads((specs_dir / iid / "tests.json").read_text())
        split = "eval" if iid in eval_ids else "train"
        manifest[split].append(iid)
        manifest["instances"][iid] = {
            "base_commit": r["base_commit"], "tool_name": r["tool_name"], "image": r.get("image_ags"),
            "spec_sha256": {name: hashlib.sha256((specs_dir / iid / name).read_bytes()).hexdigest()
                            for name in ["eval.sh", "tests.json", "test.patch", "task.yaml"]},
        }
        out_rows.append({
            "data_source": "swe-bench-ags", "agent_name": "swe_ags",
            "prompt": [{"role": "system", "content": SYSTEM_PROMPT},
                       {"role": "user", "content": USER_TEMPLATE.format(
                           repo=r["repo"], base_commit=r["base_commit"],
                           problem=r["problem_statement"],
                           f2p="\n".join(tests["FAIL_TO_PASS"]),
                           hint=_localization_hint(
                               (specs_dir / iid / "gold.patch").read_text()),
                           test_command=_test_command(
                               (specs_dir / iid / "eval.sh").read_text()))}],
            "ability": "coding", "reward_model": {"style": "rule", "ground_truth": iid},
            "extra_info": {"index": index, "instance_id": iid, "tool_name": r["tool_name"],
                           "image_ags": r.get("image_ags", ""), "max_steps": args.max_steps_hint,
                           "split": split, "validated": not args.allow_unvalidated,
                           "f2p": tests["FAIL_TO_PASS"], "p2p": tests["PASS_TO_PASS"],
                           "env": {"cwd": "/testbed"}},
        })
    if args.split_dir:
        output = kit / args.split_dir
        output.mkdir(parents=True, exist_ok=True)
        mp = output / "manifest.json"
        if mp.exists() and json.loads(mp.read_text()) != manifest:
            ap.error("Frozen split or protocol changed; refusing to overwrite")
        mp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        for split in ("train", "eval"):
            part = [r for r in out_rows if r["extra_info"]["split"] == split]
            pd.DataFrame(part).to_parquet(output / f"{split}.parquet", index=False)
        pd.DataFrame(out_rows).to_parquet(output / "all.parquet", index=False)
        print(json.dumps({"train": manifest["train"], "eval": manifest["eval"]}, indent=2))
    else:
        output = kit / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame(out_rows).to_parquet(output, index=False)
        print(f"wrote {len(out_rows)} rows to {output}")


if __name__ == "__main__":
    main()
