"""归档图表生成：训练奖励曲线 / f2p 通过率 / val 曲线 / 工程指标仪表盘。

用法:
  python controller/plot_metrics.py <archive-dir>

输入: <archive-dir>/traces_by_step.csv + metrics.csv
输出: <archive-dir>/figs/{reward_curve.png, training_dashboard.png}
"""
from __future__ import annotations

import csv
import statistics as st
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

C_RAW = "#9fb4d8"
C_MA = "#1f4e9c"
C_FIT = "#d1495b"
C_BEST = "#7cbf8a"
C_VAL = "#e69500"


def moving_average(xs: list[float], w: int = 5) -> list[float]:
    return [st.mean(xs[max(0, i - w // 2):i + w // 2 + 1]) for i in range(len(xs))]


def load(archive: Path):
    rows = [r for r in csv.DictReader(open(archive / "traces_by_step.csv"))]
    tr = [r for r in rows if 2 <= int(r["step"]) <= 47 and int(r["n"]) >= 30]
    steps = [int(r["step"]) for r in tr]
    rew = [float(r["reward"]) for r in tr]
    f2p = [float(r["f2p_rate"]) for r in tr]
    fmt = [float(r["format_errors"]) for r in tr]
    ops = [float(r["valid_actions"]) for r in tr]
    mrows = [r for r in csv.DictReader(open(archive / "metrics.csv"))]
    val = [(int(r["step"]), float(r["val-aux/swe-bench-ags/reward/mean@1"]))
           for r in mrows if r.get("val-aux/swe-bench-ags/reward/mean@1")]
    return steps, rew, f2p, fmt, ops, val


def fitline(xs, ys):
    x, y = np.array(xs, float), np.array(ys, float)
    k, b = np.polyfit(x, y, 1)
    return k, b, k * x + b


def main():
    archive = Path(sys.argv[1])
    figs = archive / "figs"
    figs.mkdir(parents=True, exist_ok=True)
    steps, rew, f2p, fmt, ops, val = load(archive)
    ma = moving_average(rew)
    k, b, fl = fitline(steps, rew)
    best = list(np.maximum.accumulate(rew))

    # ---------- 主图：训练奖励曲线 ----------
    fig, ax = plt.subplots(figsize=(10, 5.6), dpi=200)
    ax.scatter(steps, rew, s=22, color=C_RAW, zorder=3, label="Per-step reward (32 rollouts)")
    ax.plot(steps, rew, color=C_RAW, lw=1, alpha=0.6, zorder=2)
    ax.plot(steps, ma, color=C_MA, lw=2.8, zorder=4, label="Moving average (5-step)")
    ax.plot(steps, fl, color=C_FIT, lw=2, ls="--", zorder=4,
            label=f"Linear trend  (slope {k:+.5f}/step)")
    ax.plot(steps, best, color=C_BEST, lw=1.6, ls=":", zorder=3, label="Best-so-far")
    ax.set_xlabel("Training step", fontsize=12)
    ax.set_ylabel("Reward (mean F2P-based, 0-1)", fontsize=12)
    ax.set_title("SWE-RL Training Reward — Qwen3-Coder-30B-A3B (GRPO + LoRA, 4xL20)",
                 fontsize=13, fontweight="bold")
    ax.grid(alpha=0.25)
    ax.set_ylim(-0.02, 0.35)
    ax.legend(loc="upper left", fontsize=10, framealpha=0.9)
    ax.annotate(f"final MA {ma[-1]:.3f}  (from {ma[0]:.3f})",
                xy=(steps[-1], ma[-1]), xytext=(steps[-1] - 14, 0.26),
                arrowprops=dict(arrowstyle="->", color=C_MA), color=C_MA, fontsize=11)
    fig.tight_layout()
    fig.savefig(figs / "reward_curve.png")
    print("saved", figs / "reward_curve.png")

    # ---------- 仪表盘 2x2 ----------
    fig, axs = plt.subplots(2, 2, figsize=(12.5, 8), dpi=170)
    # (0,0) f2p pass rate
    a = axs[0][0]
    a.scatter(steps, f2p, s=14, color=C_RAW)
    a.plot(steps, moving_average(f2p), color=C_MA, lw=2.4)
    k2, _, fl2 = fitline(steps, f2p)
    a.plot(steps, fl2, color=C_FIT, lw=1.6, ls="--")
    a.set_title(f"F2P pass-rate  (trend {k2:+.5f}/step)", fontsize=11)
    a.grid(alpha=0.25)
    # (0,1) val reward
    a = axs[0][1]
    vx = [s for s, _ in val]
    vy = [v for _, v in val]
    a.plot(vx, vy, "o-", color=C_VAL, lw=2, ms=7)
    a.set_ylim(-0.05, 1.05)
    a.set_title("Validation reward (2 held-out instances)", fontsize=11)
    a.grid(alpha=0.25)
    # (1,0) format errors & valid ops
    a = axs[1][0]
    a.plot(steps, fmt, color="#c0504d", lw=1.8, label="format errors / rollout")
    a.plot(steps, ops, color="#4f81bd", lw=1.8, label="valid actions / rollout")
    a.legend(fontsize=9)
    a.set_title("Protocol quality over training", fontsize=11)
    a.set_xlabel("step")
    a.grid(alpha=0.25)
    # (1,1) reward distribution early vs late
    a = axs[1][1]
    half = len(rew) // 2
    a.hist([rew[:half], rew[half:]], bins=12, color=["#9fb4d8", "#1f4e9c"],
           label=[f"step {steps[0]}-{steps[half-1]}", f"step {steps[half]}-{steps[-1]}"])
    a.legend(fontsize=9)
    a.set_title("Reward distribution: first half vs second half", fontsize=11)
    a.set_xlabel("per-step reward")
    for a in axs.flat:
        a.tick_params(labelsize=9)
    fig.suptitle("SWE-RL Training Dashboard — swegym-30b-tier0-r1", fontsize=13,
                 fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    fig.savefig(figs / "training_dashboard.png")
    print("saved", figs / "training_dashboard.png")


if __name__ == "__main__":
    main()
