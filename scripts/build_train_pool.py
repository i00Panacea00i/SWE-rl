#!/usr/bin/env python3
"""画像结果 → 下一轮训练题池（instances.jsonl + task_specs）。

筛选规则（GRPO 视角）：
  learnable (1-3/4)  → 全选（组内必出正负样本，唯一有梯度的区间）
  too_easy  (4/4)    → 剔除（组内全正，零优势）
  too_hard  (0/4)    → 默认剔除；若 learnable 不足 target，按"接近通过"补齐

用法（本机，读本地 profile 数据）：
  venv/bin/python scripts/build_train_pool.py \
      --summary /tmp/profile-summary.json \
      --profile-instances data/profile/profile-instances.jsonl \
      --specs-src data/profile/task_specs \
      --out /tmp/train-pool --target 40
随后（生成 verl parquet）：
  venv/bin/python data/prepare_data.py --input /tmp/train-pool/instances.jsonl \
      --output /tmp/train-pool/train.parquet --allow-unvalidated --max-steps-hint 16
"""
from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", required=True, help="profile-summary.json")
    ap.add_argument("--profile-instances", required=True)
    ap.add_argument("--specs-src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--target", type=int, default=40)
    args = ap.parse_args()

    s = json.load(open(args.summary))
    per = s.get("per_instance") or {}
    learn = list(s.get("learnable") or [])
    hard = list(s.get("too_hard") or [])
    easy = list(s.get("too_easy") or [])

    inst = {}
    for line in open(args.profile_instances):
        if line.strip():
            r = json.loads(line)
            inst[r["instance_id"]] = r

    picked = sorted(set(learn))
    supplement: list[str] = []
    if len(picked) < args.target:
        # too_hard 全为 0/4：无区分度，按题号补齐（并在报告中标注）
        supplement = sorted(set(hard) - set(picked))[: args.target - len(picked)]
        picked += supplement

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    specs_dst = out / "task_specs"
    specs_dst.mkdir(exist_ok=True)

    missing = []
    with open(out / "instances.jsonl", "w") as f:
        for iid in picked:
            if iid not in inst:
                missing.append(iid)
                continue
            r = dict(inst[iid])
            r["validation"] = {"status": "validated"} if iid in set(learn) else {}
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
            src = Path(args.specs_src) / iid
            if src.exists() and not (specs_dst / iid).exists():
                shutil.copytree(src, specs_dst / iid)

    # 报告
    print(f"[train-pool] 训练题池 {len(picked)} 题（目标 {args.target}）")
    print(f"  learnable(1-3/4): {len(learn)} 题 ← 有梯度信号")
    print(f"  too_hard 补齐   : {len(supplement)} 题 ← 无信号，仅作分母（如果 learnable 不足）")
    print(f"  too_easy 剔除   : {len(easy)} 题（4/4，零优势）")
    if missing:
        print(f"  ⚠️ 缺元数据（跳过）: {missing}")
    print("  逐题 p̂：")
    for iid in picked:
        p = per.get(iid, {})
        print(f"    {iid:<34} {p.get('resolved', '?')}/{p.get('n', '?')}  ({p.get('band', '?')})")
    (out / "pool-report.json").write_text(json.dumps({
        "target": args.target, "picked": picked, "learnable": learn,
        "supplement_from_too_hard": supplement, "excluded_too_easy": easy,
        "per_instance": per,
    }, ensure_ascii=False, indent=1))
    print(f"[train-pool] → {out}/instances.jsonl + task_specs/ ({len(list(specs_dst.iterdir()))} 题) + pool-report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
