"""verl 训练日志 → reward 曲线图（验收：reward 上升趋势，matplotlib 本地方案）。

用法：
  venv/bin/python controller/plot_reward.py \
      --log /mnt/cfs/swe-rl/logs/train-*.log \
      --output /mnt/cfs/swe-rl/eval_reports/reward_curve.png

兼容两种日志形态：
  1) verl trainer 逐步打印：`step:N - key1:v1 key2:v2 ...`（含 critic/rewards/mean）
  2) 单指标 JSON 行（{"step":N, "critic/rewards/mean":v, ...}）
"""
from __future__ import annotations

import argparse
import glob
import json
import re
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

# 验收关注的指标（正则匹配日志中的 key）
WANTED = [
    "critic/rewards/mean",
    "actor/pg_loss",
    "actor/kl_loss",
    "response_length/mean",
]


def parse_log(text: str) -> dict[str, list[tuple[int, float]]]:
    series: dict[str, list[tuple[int, float]]] = defaultdict(list)
    # 形态 1：step:N - k1:v1 k2:v2（verl tqdm/print 风格）
    for m in re.finditer(r"step:(\d+)\s+-\s+(.+)", text):
        step = int(m.group(1))
        for km in re.finditer(r"([\w/\[\]\.]+):(-?\d+\.?\d*(?:e[+-]?\d+)?)", m.group(2)):
            key, val = km.group(1), float(km.group(2))
            if any(key.startswith(w) or w in key for w in WANTED):
                series[key].append((step, val))
    # 形态 2：JSON 行
    if not series:
        for line in text.splitlines():
            if not line.strip().startswith("{"):
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            step = d.get("step") or d.get("global_step")
            if step is None:
                continue
            for k, v in d.items():
                if isinstance(v, (int, float)) and (
                        any(k.startswith(w) or w in k for w in WANTED)):
                    series[k].append((int(step), float(v)))
    return series


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True, help="verl 训练日志（支持通配符）")
    ap.add_argument("--output", default="reward_curve.png")
    ap.add_argument("--smooth", type=int, default=5, help="滑动平均窗口")
    args = ap.parse_args()

    files = sorted(glob.glob(args.log))
    assert files, f"no log file: {args.log}"
    text = "\n".join(Path(f).read_text(errors="ignore") for f in files)
    series = parse_log(text)
    assert series, "日志中未解析出任何指标（检查 verl 日志格式）"

    # 主图：reward（滑动平均 + 原始散点）；副图：loss/长度
    reward_keys = [k for k in series if "reward" in k]
    other_keys = [k for k in series if "reward" not in k][:2]
    fig, axes = plt.subplots(1 + bool(other_keys), 1, figsize=(10, 4 + 3 * bool(other_keys)))
    ax0 = axes[0] if hasattr(axes, "__len__") else axes

    for k in reward_keys:
        pts = sorted(set(series[k]))
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        ax0.scatter(xs, ys, s=8, alpha=0.3, label=f"{k} (raw)")
        if len(ys) >= args.smooth:
            sm = [sum(ys[max(0, i - args.smooth + 1):i + 1]) /
                  len(ys[max(0, i - args.smooth + 1):i + 1]) for i in range(len(ys))]
            ax0.plot(xs, sm, linewidth=2, label=f"{k} (MA{args.smooth})")
    ax0.set_xlabel("step")
    ax0.set_ylabel("reward")
    ax0.set_title("GRPO training reward curve (fail->pass / total F2P)")
    ax0.legend(fontsize=8)
    ax0.grid(alpha=0.3)

    if other_keys:
        ax1 = axes[1]
        for k in other_keys:
            pts = sorted(set(series[k]))
            ax1.plot([p[0] for p in pts], [p[1] for p in pts], label=k)
        ax1.set_xlabel("step")
        ax1.legend(fontsize=8)
        ax1.grid(alpha=0.3)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    print(f"saved → {out}")
    for k, pts in series.items():
        print(f"  {k}: {len(pts)} points, step {min(p[0] for p in pts)}-"
              f"{max(p[0] for p in pts)}")


if __name__ == "__main__":
    main()
