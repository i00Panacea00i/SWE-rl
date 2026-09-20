"""解析训练轨迹（episode + judge）→ 轨迹级 CSV + 分步聚合 CSV（归档分析用）。

用法:
  python controller/parse_traces.py <traces-dir> <out-dir>

输入结构: <traces-dir>/train/step-N/<instance>/<episode_id>/{episode.json, judge/result.json}
"""
from __future__ import annotations

import csv
import glob
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


def parse_traces(root: Path) -> list[dict]:
    rows = []
    for ep in glob.glob(str(root / "train" / "step-*" / "*" / "*" / "episode.json")):
        m = re.search(r"/step-(\d+)/", ep)
        if not m:
            continue
        step = int(m.group(1))
        d = os.path.dirname(ep)
        rec = {"step": step}
        try:
            e = json.load(open(ep))
            rec["instance_id"] = e.get("instance_id", "")
            steps = e.get("steps", [])
            rec["num_turns"] = len(steps)
            rec["format_errors"] = sum(1 for s in steps if s.get("kind") == "format_error")
            rec["valid_actions"] = sum(1 for s in steps
                                       if s.get("kind") in ("inspect", "execute", "edit", "test"))
            rec["edits"] = sum(1 for s in steps if s.get("kind") == "edit")
            rec["tests_run"] = sum(1 for s in steps if s.get("kind") == "test")
        except Exception:
            continue
        rj = os.path.join(d, "judge", "result.json")
        try:
            j = json.load(open(rj))
            rec["reward"] = j.get("reward", 0.0)
            rec["resolved"] = bool(j.get("resolved"))
            g = j.get("grade") or {}
            np_, nf = len(g.get("f2p_passed") or []), len(g.get("f2p_failed") or [])
            rec["f2p_pass"] = np_
            rec["f2p_fail"] = nf
            rec["f2p_rate"] = np_ / (np_ + nf) if (np_ + nf) else 0.0
        except Exception:
            rec["reward"] = None
        rows.append(rec)
    return sorted(rows, key=lambda r: (r["step"], r.get("instance_id", "")))


def aggregate(rows: list[dict], keys: list[str]) -> dict[int, dict]:
    by_step: dict[int, list[dict]] = defaultdict(list)
    for r in rows:
        by_step[r["step"]].append(r)
    out = {}
    for step, rs in sorted(by_step.items()):
        agg = {"step": step, "n": len(rs)}
        for k in keys:
            vals = [r[k] for r in rs if r.get(k) is not None]
            agg[k] = round(sum(vals) / len(vals), 4) if vals else ""
        agg["resolved_sum"] = sum(1 for r in rs if r.get("resolved"))
        out[step] = agg
    return out


def main():
    root, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = parse_traces(root)
    print(f"轨迹数: {len(rows)}")
    keys = ["reward", "resolved", "f2p_rate", "format_errors", "valid_actions",
            "edits", "tests_run", "num_turns"]
    with open(out_dir / "traces.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["step", "instance_id", "reward", "resolved",
                                          "f2p_pass", "f2p_fail", "f2p_rate", "num_turns",
                                          "format_errors", "valid_actions", "edits", "tests_run"])
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in w.fieldnames})
    agg = aggregate(rows, keys)
    with open(out_dir / "traces_by_step.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["step", "n", "reward", "resolved", "f2p_rate",
                                          "format_errors", "valid_actions", "edits",
                                          "tests_run", "num_turns", "resolved_sum"])
        w.writeheader()
        for s in sorted(agg):
            w.writerow(agg[s])
    # 训练期总览（排除 step<=5 的工程修复期）
    train = [r for r in rows if r["step"] > 5 and r.get("reward") is not None]
    if train:
        n = len(train)
        print(f"有效训练轨迹（step>5）: {n} | 满分: {sum(1 for r in train if r['resolved'])}"
              f" ({sum(1 for r in train if r['resolved'])/n*100:.1f}%)")
        print(f"f2p 通过率均值: {sum(r['f2p_rate'] for r in train)/n:.4f}")
        print(f"format_error/轨迹: {sum(r['format_errors'] for r in train)/n:.1f}"
              f" | 有效操作/轨迹: {sum(r['valid_actions'] for r in train)/n:.1f}")
        print(f"产出补丁的轨迹: {sum(1 for r in train if not r.get('patch_empty'))}")
    print(f"输出: {out_dir/'traces.csv'} + {out_dir/'traces_by_step.csv'}")


if __name__ == "__main__":
    main()
