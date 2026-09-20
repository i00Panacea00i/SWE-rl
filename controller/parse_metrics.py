"""从训练日志解析逐步指标 → CSV（归档用）。

用法:
  python controller/parse_metrics.py <train-full.log> <out-dir>
"""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

FIELDS = [
    "critic/rewards/mean", "critic/rewards/max", "critic/rewards/min",
    "critic/score/mean", "critic/score/max",
    "critic/advantages/mean",
    "actor/entropy", "actor/grad_norm", "actor/kl_loss",
    "training/num_turns/mean", "response_length/mean", "response_length/clip_ratio",
    "timing_s/step", "perf/throughput",
    "val-aux/swe-bench-ags/reward/mean@1", "val-core/swe-bench-ags/acc/mean@1",
]


def parse(log_path: Path) -> list[dict]:
    rows: dict[int, dict] = {}
    step_re = re.compile(r"step:(\d+)\s+-\s+")
    for line in log_path.read_text(errors="ignore").splitlines():
        m = step_re.search(line)
        if not m:
            continue
        step = int(m.group(1))
        row = rows.setdefault(step, {"step": step})
        for f in FIELDS:
            fm = re.search(re.escape(f) + r":(-?[0-9.]+)", line)
            if fm:
                short = f.split("/")[-1].replace("@1", "")
                row[f] = float(fm.group(1))
    return [rows[k] for k in sorted(rows)]


def main():
    src, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = parse(src)
    keys = ["step"] + FIELDS
    with open(out_dir / "metrics.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in keys})
    print(f"解析 {len(rows)} 步 → {out_dir/'metrics.csv'}")
    scored = [r for r in rows if "critic/rewards/mean" in r]
    if scored:
        first, last = scored[0], scored[-1]
        print(f"train reward: 首步 {first['step']}={first['critic/rewards/mean']:.4f} "
              f"→ 末步 {last['step']}={last['critic/rewards/mean']:.4f}")
        best = max(scored, key=lambda r: r["critic/rewards/mean"])
        print(f"最高单步: step {best['step']} = {best['critic/rewards/mean']:.4f}")
    vals = [r for r in rows if "val-aux/swe-bench-ags/reward/mean@1" in r]
    print("val 记录:", ", ".join(f"step{r['step']}={r['val-aux/swe-bench-ags/reward/mean@1']}"
                                 for r in vals))


if __name__ == "__main__":
    main()
