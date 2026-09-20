"""episode.json 轨迹 → VERL rollout 格式 parquet（离线分析 / 数据回放）。

每条 episode 的 token_alignment（prompt_ids/response_ids/response_mask/
response_logprobs）本身就是 VERL rollout 的原生字段；本工具把轨迹目录
聚合为单个 parquet，可直接用于：
  - 离线分析（奖励分布、操作类别、步数、测试通过率）
  - 数据回放 / 过滤（挑出成功或近成功轨迹做 SFT / 拒绝采样）

用法：
  venv/bin/python data/export_traces.py \
      --traces /tmp/v4-ops/recovery-14b-fullbatch-v4-warmup-misconfigured-batch4-n2 \
      --output /tmp/traces-export.parquet
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_episodes(traces_dir: Path) -> list[dict]:
    eps = []
    for p in sorted(traces_dir.rglob("episode.json")):
        try:
            d = json.loads(p.read_text())
        except json.JSONDecodeError:
            continue
        if "token_alignment" not in d:
            continue
        d["_path"] = str(p)
        eps.append(d)
    return eps


def to_row(d: dict) -> dict:
    ta = d["token_alignment"]
    final = d.get("final", {})
    steps = d.get("steps", [])
    return {
        "episode_id": d.get("episode_id", ""),
        "instance_id": d.get("instance_id", ""),
        "phase": d.get("phase", ""),
        "global_step": d.get("global_step", -1),
        "split": d.get("split", ""),
        "tool_name": d.get("tool_name", ""),
        "sandbox_id": d.get("sandbox_id", ""),
        # VERL rollout 原生字段
        "prompt_ids": ta.get("prompt_ids", []),
        "response_ids": ta.get("response_ids", []),
        "response_mask": ta.get("response_mask", []),
        "response_logprobs": ta.get("response_logprobs", []),
        # 奖励（测试通过率）与判分
        "reward": float(final.get("reward", 0.0)),
        "resolved": bool(final.get("resolved", False)),
        "f2p_passed": (final.get("grade") or {}).get("f2p_passed", []),
        "f2p_failed": (final.get("grade") or {}).get("f2p_failed", []),
        "failure_kind": final.get("failure_kind"),
        # 结构化 tracing 摘要
        "num_steps": len(steps),
        "shell_operations": d.get("shell_operations", 0),
        "operation_kinds": json.dumps(d.get("operation_kinds", {}), ensure_ascii=False),
        "stop_reason": d.get("stop_reason", ""),
        "changed_files": d.get("changed_files", []),
        "trace_path": str(d.get("_path", "")),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--traces", required=True, help="轨迹根目录（递归查找 episode.json）")
    ap.add_argument("--output", required=True, help="输出 parquet 路径")
    ap.add_argument("--min-reward", type=float, default=None,
                    help="仅导出 reward >= 阈值的轨迹（拒绝采样用）")
    args = ap.parse_args()

    import pandas as pd

    root = Path(args.traces)
    eps = load_episodes(root)
    rows = []
    for d in eps:
        row = to_row(d)
        if args.min_reward is not None and row["reward"] < args.min_reward:
            continue
        rows.append(row)
    if not rows:
        raise SystemExit(f"没有可导出的轨迹（{root}）")
    df = pd.DataFrame(rows)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(out, index=False)
    print(json.dumps({
        "episodes": len(rows),
        "reward_mean": round(float(df["reward"].mean()), 4),
        "reward_max": float(df["reward"].max()),
        "resolved": int(df["resolved"].sum()),
        "avg_steps": round(float(df["num_steps"].mean()), 1),
        "output": str(out),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
