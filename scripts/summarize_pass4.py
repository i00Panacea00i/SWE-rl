#!/usr/bin/env python3
"""从轨迹目录汇总 pass@k（跨分批采样）。

背景：AGS 沙箱配额上限 100，n=4 需拆为两批（--n 2 --sample-offset 0/2）。
本脚本直接扫描 traces/<tag>/vllm-pass4/*/result.json（目录名 <iid>__s<k>），
按题聚合全部采样，输出 pass@1 / pass@k（k=每题实际采样数）与两组对比。

用法：
  python scripts/summarize_pass4.py \
    --base /mnt/cfs/swe-rl/traces/eval-base-t0/vllm-pass4 \
    --lora /mnt/cfs/swe-rl/traces/eval-lora-t0/vllm-pass4
"""
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


def collect(root: Path) -> dict[str, list[dict]]:
    per: dict[str, list[dict]] = defaultdict(list)
    if not root.exists():
        return per
    for d in sorted(root.iterdir()):
        if not d.is_dir() or "__s" not in d.name:
            continue
        iid = d.name.rsplit("__s", 1)[0]
        res_file = d / "result.json"
        rec = {"resolved": False, "reward": 0.0, "f2p": 0, "f2p_total": 0, "error": None}
        if res_file.exists():
            try:
                r = json.loads(res_file.read_text())
                g = r.get("grade") or {}
                rec["resolved"] = bool(r.get("resolved"))
                rec["reward"] = r.get("reward")
                rec["f2p"] = len(g.get("f2p_passed") or [])
                rec["f2p_total"] = rec["f2p"] + len(g.get("f2p_failed") or [])
                rec["error"] = r.get("error")
            except Exception as e:  # noqa: BLE001
                rec["error"] = f"parse: {str(e)[:80]}"
        per[iid].append(rec)
    return per


def report(tag: str, per: dict[str, list[dict]]) -> dict:
    n_inst = len(per)
    n_traj = sum(len(v) for v in per.values())
    pass_any = sum(1 for v in per.values() if any(r["resolved"] for r in v))
    traj_resolved = sum(1 for v in per.values() for r in v if r["resolved"])
    avg_samples = round(n_traj / max(1, n_inst), 2)
    f2p_num = sum(r["f2p"] for v in per.values() for r in v)
    f2p_den = sum(r["f2p_total"] for v in per.values() for r in v)
    print(f"=== {tag} ===")
    print(f"  题数 {n_inst} | 轨迹 {n_traj} | 平均采样 {avg_samples}/题")
    print(f"  pass@any(=pass@{int(avg_samples)} 近似) : {pass_any}/{n_inst} = {pass_any / max(1, n_inst):.3f}")
    print(f"  轨迹级通过率        : {traj_resolved}/{n_traj} = {traj_resolved / max(1, n_traj):.3f}")
    print(f"  f2p 通过率(部分)    : {f2p_num}/{f2p_den} = {f2p_num / max(1, f2p_den):.4f}")
    return {"tag": tag, "instances": n_inst, "trajectories": n_traj,
            "pass_any": pass_any, "pass_any_rate": round(pass_any / max(1, n_inst), 4),
            "traj_rate": round(traj_resolved / max(1, n_traj), 4),
            "f2p_rate": round(f2p_num / max(1, f2p_den), 4),
            "per_instance": {i: {"samples": len(v),
                                 "resolved_count": sum(1 for r in v if r["resolved"]),
                                 "f2p": [r["f2p"] for r in v]}
                             for i, v in per.items()}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--lora", required=True)
    ap.add_argument("--out", default="/tmp/pass4-summary.json")
    args = ap.parse_args()

    pb = collect(Path(args.base))
    pl = collect(Path(args.lora))
    rb = report("base", pb)
    rl = report("lora(step-50, merged)", pl)

    print("\n=== 对比 ===")
    print(f"{'指标':<22}{'base':>10}{'lora':>10}")
    print(f"{'pass@any(题级)':<22}{rb['pass_any_rate']:>10.3f}{rl['pass_any_rate']:>10.3f}")
    print(f"{'轨迹级通过率':<20}{rb['traj_rate']:>10.3f}{rl['traj_rate']:>10.3f}")
    print(f"{'f2p 通过率':<21}{rb['f2p_rate']:>10.4f}{rl['f2p_rate']:>10.4f}")

    bp = {i for i, v in rb["per_instance"].items() if v["resolved_count"]}
    lp = {i for i, v in rl["per_instance"].items() if v["resolved_count"]}
    print(f"\nbase 通过题({len(bp)}): {sorted(bp)}")
    print(f"lora 通过题({len(lp)}): {sorted(lp)}")
    print(f"仅 lora 新增: {sorted(lp - bp)} | 仅 base: {sorted(bp - lp)}")

    Path(args.out).write_text(json.dumps({"base": rb, "lora": rl}, ensure_ascii=False, indent=2))
    print(f"\n明细已写 {args.out}")


if __name__ == "__main__":
    main()
