"""AGS 沙箱批量验证驱动（SKILL2 模式：驱动在 CVM、执行在沙箱、入库在本地）。

对每道题执行双向验证：
  baseline（全新沙箱）: 跑官方 eval.sh → 期望 F2P 全 FAIL、P2P 全 PASS
  golden  ×N（全新沙箱）: git apply 金标补丁 → eval.sh → 期望 F2P+P2P 全 PASS
  N 次结果不一致 → flaky（invalid 留痕，不入训练集）

硬性约定（沿自上个项目踩坑 #10/#11）：
  1. commands.run(..., user="root")——规避 git dubious-ownership 静默失败
  2. CommandExitException 按正常结果解析（exit≠0 是业务码）
  3. 每个 (instance, mode, run) 用全新沙箱——镜像内存在构建期未提交修改
     （如 sphinx 官方对 tox.ini 的 sed），禁止跨模式复用、禁止全树 reset

用法：
  set -a && source .env && set +a
  venv/bin/python sandbox/validate_swe_ags.py --verify-runs 2 \
      --output-jsonl output/merged/benchmark.jsonl
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import (Evidence, Instance, build_cmds, check_mode,  # noqa: E402
                     extract_test_log, grade, load_instances)

from e2b_code_interpreter import Sandbox  # noqa: E402
from e2b.sandbox.commands.command_handle import CommandExitException  # noqa: E402
from e2b.exceptions import TimeoutException as E2BTimeout  # noqa: E402

KIT_ROOT = Path(__file__).resolve().parent.parent


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def append_jsonl_atomic(path: Path, record: dict):
    """flock + 临时文件 + fsync 原子追加"""
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
        f.flush()
        os.fsync(f.fileno())
    with open(path, "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            f.write(tmp.read_text())
            f.flush()
            os.fsync(f.fileno())
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
    tmp.unlink()


def load_validated_ids(path: Path) -> set:
    if not path.exists():
        return set()
    return {json.loads(l)["instance_id"]
            for l in path.read_text().splitlines() if l.strip()}


class AgsRunner:
    """单个 (instance, mode) 在全新沙箱中执行并判分"""

    def __init__(self, sandbox_timeout: int, evidence: Evidence):
        self.sandbox_timeout = sandbox_timeout
        self.evidence = evidence

    def _run_cmd(self, sb, cmd: str, timeout: int):
        t0 = time.time()
        try:
            r = sb.commands.run(cmd, user="root", timeout=timeout)
            code, out, err = r.exit_code, r.stdout, r.stderr
        except CommandExitException as e:  # exit≠0 是正常业务码
            code, out, err = e.exit_code, e.stdout, e.stderr
        except E2BTimeout:
            code, out, err = 124, "", f"command timeout after {timeout}s"
        self.evidence.record(cmd, code, int((time.time() - t0) * 1000), out, err)
        return code, out, err

    def run(self, inst: Instance, mode: str) -> dict:
        """返回 {ok, why, grade, sandbox_id, env_fingerprint}"""
        sb, sid, fp = None, "", ""
        g = {"status": "harness_error", "detail": "sandbox create failed"}
        try:
            sb = Sandbox.create(template=inst.tool_name,
                                timeout=self.sandbox_timeout)
            sid = sb.sandbox_id
            sb.files.write("/tmp/eval.sh", inst.eval_sh)
            sb.files.write("/tmp/gold.patch", inst.gold_patch)
            for c in build_cmds(inst, mode):
                code, out, err = self._run_cmd(sb, c["cmd"], c["timeout"])
                if c["name"] == "env_fingerprint":
                    fp = out.strip()[:300]
                if not c["name"].startswith("eval_"):
                    if code != 0:
                        g = {"status": "harness_error",
                             "detail": f"命令 {c['name']} 失败 exit={code}: "
                                       f"{(err or out)[-300:]}"}
                        break
                else:
                    log = extract_test_log(out, err)
                    g = grade(inst, log)
            ok, why = check_mode(mode, g) if g["status"] == "ok" else (False, g.get("detail", "error"))
            return {"ok": ok, "why": why, "grade": g,
                    "sandbox_id": sid, "env_fingerprint": fp}
        except Exception as e:
            return {"ok": False, "why": f"sandbox_error: {str(e)[:300]}",
                    "grade": g, "sandbox_id": sid, "env_fingerprint": fp}
        finally:
            if sb is not None:
                try:
                    sb.kill()  # 用完即杀
                except Exception:
                    pass


def validate_instance(inst: Instance, modes: list[str], verify_runs: int,
                      sandbox_timeout: int, evidence: Evidence) -> dict:
    runner = AgsRunner(sandbox_timeout, evidence)
    mode_results = {}
    for mode in modes:
        runs = verify_runs if mode == "golden" else 1
        mode_results[mode] = [runner.run(inst, mode) for _ in range(runs)]

    # 判定
    base = mode_results.get("baseline", [None])[0]
    golds = mode_results.get("golden", [])
    status, failure_mode = "validated", ""
    if base is not None and not base["ok"]:
        status, failure_mode = "invalid", \
            "baseline_pass" if "假阳性" in base["why"] else "baseline_error"
    elif golds:
        if not all(g["ok"] for g in golds):
            if any(g["ok"] for g in golds):
                status, failure_mode = "invalid", "flaky"
            else:
                status, failure_mode = "invalid", "f2p_fail"
    return {
        "instance_id": inst.instance_id,
        "status": status,
        "failure_mode": failure_mode,
        "mode_results": mode_results,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--instances", default="all")
    ap.add_argument("--modes", default="baseline,golden")
    ap.add_argument("--verify-runs", type=int, default=2,
                    help="golden 模式重复次数（一致性/flaky 拦截）")
    ap.add_argument("--output-jsonl", default="output/merged/benchmark.jsonl")
    ap.add_argument("--invalid-jsonl", default="output/artifacts/invalid-instances.jsonl")
    ap.add_argument("--report-dir", default="output/artifacts")
    ap.add_argument("--sandbox-timeout", type=int, default=3600)
    ap.add_argument("--parallel", type=int, default=1,
                    help="并发验证的实例数（每实例内部仍是串行沙箱）")
    ap.add_argument("--evidence-dir", default="output/artifacts")
    args = ap.parse_args()

    ids = None if args.instances == "all" else args.instances.split(",")
    insts = load_instances(ids)

    # G0 预检：本地协议文件完整性（镜像/tag/工具已在 harness 加载时校验）
    for i in insts:
        assert i.f2p, f"{i.instance_id} F2P 为空"
    print(f"[G0] 协议文件校验通过，共 {len(insts)} 题；"
          f"环境: E2B_DOMAIN={os.environ.get('E2B_DOMAIN', '(未设置!)')}")

    out_path = KIT_ROOT / args.output_jsonl
    out_path.parent.mkdir(parents=True, exist_ok=True)
    report_dir = KIT_ROOT / args.report_dir
    report_dir.mkdir(parents=True, exist_ok=True)

    done = load_validated_ids(out_path)
    run_id = time.strftime("ags-%Y%m%d-%H%M%S")
    todo = [i for i in insts if i.instance_id not in done]
    for i in insts:
        if i.instance_id in done:
            print(f"--- {i.instance_id}: 已 validated，跳过（幂等）")

    def process(inst) -> dict:
        """单实例验证 → (res 含记录写入结果)；线程安全（append 有 flock）"""
        print(f"--- {inst.instance_id} (tool={inst.tool_name})")
        ev = Evidence(run_id)
        t0 = time.time()
        res = validate_instance(inst, args.modes.split(","), args.verify_runs,
                                args.sandbox_timeout, ev)
        res["duration_ms"] = int((time.time() - t0) * 1000)

        ev_path = (Path(args.evidence_dir)
                   / f"execution-evidence-{run_id}-{inst.instance_id}.json")
        ev.save(KIT_ROOT / ev_path)

        base = res["mode_results"].get("baseline", [{}])[0] or {}
        golds = res["mode_results"].get("golden", [])
        rec = {
            "instance_id": inst.instance_id,
            "repo": inst.repo,
            "base_commit": inst.base_commit,
            "problem_statement": inst.problem_statement,
            "FAIL_TO_PASS": inst.f2p,
            "PASS_TO_PASS": inst.p2p,
            "tool_name": inst.tool_name,
            "image_ags": inst.image_ags,
            "validation": {
                "status": res["status"],
                "failure_mode": res["failure_mode"] or None,
                "baseline_mode": base.get("why"),
                "golden_mode": [g["why"] for g in golds],
                "golden_consistent": bool(golds) and all(g["ok"] for g in golds),
                "runs": args.verify_runs,
                "runtime": "tencent-ags-sandbox",
                "validated_at": now_iso(),
                "duration_ms": res["duration_ms"],
                "sandbox_ids": [base.get("sandbox_id")] + [g.get("sandbox_id") for g in golds],
                "env_fingerprint": base.get("env_fingerprint", "")[:300],
                "evidence_file": str(ev_path),
            },
        }
        if res["status"] == "validated":
            append_jsonl_atomic(out_path, rec)
            print(f"    {inst.instance_id}: VALIDATED ({res['duration_ms']}ms)")
        else:
            append_jsonl_atomic(KIT_ROOT / args.invalid_jsonl, {
                "instance_id": inst.instance_id, "status": "invalid",
                "failure_mode": res["failure_mode"],
                "why": (golds[-1]["why"] if golds else base.get("why")),
                "duration_ms": res["duration_ms"]})
            print(f"    {inst.instance_id}: INVALID ({res['failure_mode']})")
        return res

    results = []
    if args.parallel > 1:
        import concurrent.futures
        with concurrent.futures.ThreadPoolExecutor(args.parallel) as ex:
            results = list(ex.map(process, todo))
    else:
        results = [process(i) for i in todo]

    # 报告
    total = len(results)
    validated = sum(1 for r in results if r["status"] == "validated")
    rate = validated / total if total else 0
    report = {
        "run_id": run_id, "runtime": "tencent-ags-sandbox",
        "total": total, "validated": validated,
        "invalid": total - validated, "validated_rate": round(rate, 3),
        "gate": "PASS (>=80%)" if rate >= 0.8 else ("SMOKE PASS (>=60%)" if rate >= 0.6 else "FAIL (<60%)"),
        "failure_modes": {},
        "output_jsonl": str(out_path),
        "generated_at": now_iso(),
    }
    for r in results:
        if r["status"] == "invalid":
            report["failure_modes"][r["failure_mode"]] = \
                report["failure_modes"].get(r["failure_mode"], 0) + 1
    rp = report_dir / f"validation-report-{run_id}.json"
    rp.write_text(json.dumps(report, ensure_ascii=False, indent=1))
    print(json.dumps(report, ensure_ascii=False, indent=1))
    sys.exit(0 if rate >= 0.6 else 1)


if __name__ == "__main__":
    main()
