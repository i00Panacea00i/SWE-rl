#!/usr/bin/env python3
"""画像汇总：读 profile-t0 轨迹 → 每题 p̂ 分层 → 输出推荐训练题单。

分层口径（4 次采样）：
  learnable : 1-3/4 通过（GRPO 组内必出正负样本 → 有梯度）
  too_easy  : 4/4（组内全正 → 零优势）
  too_hard  : 0/4（组内全负 → 零优势）

输出：/mnt/cfs/swe-rl/logs/profile-summary.json（per_instance + 分层题单）
"""
from __future__ import annotations

import glob
import json
from collections import Counter, defaultdict

TRACE = '/mnt/cfs/swe-rl/traces/profile-t0/vllm'
OUT = '/mnt/cfs/swe-rl/logs/profile-summary.json'


def main() -> int:
    per: dict[str, list[int]] = defaultdict(list)
    for f in glob.glob(f'{TRACE}/*/result.json'):
        try:
            r = json.load(open(f))
        except Exception:
            continue
        iid = r.get('instance_id') or f.split('/')[-2].rsplit('__s', 1)[0]
        per[iid].append(1 if r.get('resolved') else 0)

    rows = []
    for iid, v in sorted(per.items()):
        n, k = len(v), sum(v)
        p = k / n
        band = 'learnable' if 0 < p < 1 else ('too_easy' if p == 1 else 'too_hard')
        rows.append({'instance_id': iid, 'n': n, 'resolved': k, 'p': round(p, 3), 'band': band})

    c = Counter(r['band'] for r in rows)
    summary = {
        'scanned': len(rows),
        'bands': dict(c),
        'learnable': [r['instance_id'] for r in rows if r['band'] == 'learnable'],
        'too_easy': [r['instance_id'] for r in rows if r['band'] == 'too_easy'],
        'too_hard': [r['instance_id'] for r in rows if r['band'] == 'too_hard'],
        'per_instance': {r['instance_id']: r for r in rows},
    }
    json.dump(summary, open(OUT, 'w'), ensure_ascii=False, indent=1)
    print(f"[画像汇总] 扫描 {len(rows)} 题 | 可学习(1-3/4) {c.get('learnable', 0)}"
          f" | 全败(0/4) {c.get('too_hard', 0)} | 全通(4/4) {c.get('too_easy', 0)}")
    print(f"[画像汇总] 可学习题单（{len(summary['learnable'])} 题）:")
    for iid in summary['learnable']:
        r = summary['per_instance'][iid]
        print(f"    {iid:<34} {r['resolved']}/{r['n']}")
    print(f"[画像汇总] → {OUT}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
