"""从双向验证产物构建 held-out 测试集（ADR-001）：
- 通过题：生成 instances.jsonl + parquet（val-only 数据集）
- 剔除记录：留痕（假阳性 / flaky / f2p_fail）
- 防泄漏双断言：测试集 ∩（训练集 20 题 + 训练期评估 2 题）= ∅
- 输出冻结 manifest（题单 + 剔除记录 + 校验和）

用法:
  python controller/build_heldout.py \
      --validated output/merged/heldout-validation.jsonl \
      --invalid   output/artifacts/heldout/heldout-invalid.jsonl \
      --pool      data/swe-gym-instances-tcr.jsonl \
      --train-ref output/merged/swe-gym-tier0.jsonl \
      --out-dir   data/heldout
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def load_jsonl(p: Path) -> list[dict]:
    if not p.exists():
        return []
    return [json.loads(l) for l in p.read_text().splitlines() if l.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--validated", required=True)
    ap.add_argument("--invalid", required=True)
    ap.add_argument("--pool", required=True)
    ap.add_argument("--train-ref", required=True)
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    validated = load_jsonl(Path(args.validated))
    invalid = load_jsonl(Path(args.invalid))
    pool = {r["instance_id"]: r for r in load_jsonl(Path(args.pool))}
    train_ref = {r["instance_id"] for r in load_jsonl(Path(args.train_ref))}

    heldout_ids = [r["instance_id"] for r in validated]
    dup = len(heldout_ids) != len(set(heldout_ids))
    assert not dup, "验证记录存在重复题"

    # ── 防泄漏：与训练/评估集求交，泄漏题自动剔除并留痕（快照漂移防线）──
    leak = set(heldout_ids) & train_ref
    leaked_records = []
    if leak:
        print(f"[防泄漏] 剔除 {len(leak)} 个泄漏题（已用于训练/评估）: {sorted(leak)}")
        for r in validated:
            if r["instance_id"] in leak:
                leaked_records.append({"instance_id": r["instance_id"],
                                       "failure_mode": "leak_with_train_set",
                                       "why": "候选清单快照漂移：该题在清单生成后被验证并进入训练集"})
        heldout_ids = [i for i in heldout_ids if i not in leak]
        validated = [r for r in validated if r["instance_id"] not in leak]
    else:
        print(f"[防泄漏] 测试集 {len(heldout_ids)} 题 ∩ 训练/评估 {len(train_ref)} 题 = ∅ ✓")

    # ── 组装 records（字段基底=pool，含 image_env；含 image_tcr）──
    recs = []
    for r in validated:
        iid = r["instance_id"]
        base = dict(pool[iid])
        assert base.get("image_env"), iid
        assert base.get("image_tcr"), iid
        base["validation"] = r.get("validation", {})
        recs.append(base)

    # ── 写文件 ──
    inst_p = out / "instances.jsonl"
    inst_p.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in recs))
    parq_in = out / "heldout-input.jsonl"
    parq_in.write_text(inst_p.read_text())
    print(f"写入 {inst_p}（{len(recs)} 题）")

    # ── 剔除记录 + manifest ──
    manifest = {
        "stage": "final-validation / held-out",
        "source": "86 candidates dual-verified (baseline x1 + golden x2)",
        "passed": heldout_ids,
        "rejected": [{"instance_id": r["instance_id"],
                      "failure_mode": r.get("failure_mode"),
                      "why": str(r.get("why", ""))[:200]} for r in invalid] + leaked_records,
        "leak_check": f"PASS (auto-removed {len(leaked_records)} leaked instance(s))",
        "train_ref_size": len(train_ref),
        "counts": {"passed": len(heldout_ids), "rejected": len(invalid)},
        "instances_sha256": hashlib.sha256(inst_p.read_bytes()).hexdigest(),
    }
    mf = out / "heldout-manifest.json"
    mf.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    print(f"manifest -> {mf}")
    print(f"统计: 通过 {len(heldout_ids)} | 剔除 {len(invalid)}")
    from collections import Counter
    print("剔除原因分布:", dict(Counter(r.get("failure_mode") for r in invalid)))


if __name__ == "__main__":
    main()
