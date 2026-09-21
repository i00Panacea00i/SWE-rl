#!/usr/bin/env python3
"""停止账号下全部 AGS 沙箱实例（配额清理）。

场景：AGS 沙箱实例配额上限 100（LimitExceeded.SandboxInstance）。
评估 driver 异常退出（如配额超限、被杀 Pod）时，已创建的沙箱仍占用配额，
导致后续批次全部创建失败。本脚本列出全部实例并逐一停止。

用法：
  python sandbox/cleanup_sandboxes.py --dry-run   # 只看状态分布
  python sandbox/cleanup_sandboxes.py             # 全部停止
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ags_instance import _client, stop_instance  # noqa: E402
from tencentcloud.ags.v20250920 import models  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=100)
    args = ap.parse_args()

    client = _client()
    insts, offset = [], 0
    while True:
        req = models.DescribeSandboxInstanceListRequest()
        req.Limit = args.limit
        req.Offset = offset
        resp = client.DescribeSandboxInstanceList(req)
        page = list(resp.InstanceSet or [])
        insts.extend(page)
        if len(page) < args.limit or offset > 500:
            break
        offset += args.limit

    by_status: dict[str, int] = {}
    for i in insts:
        by_status[i.Status] = by_status.get(i.Status, 0) + 1
    print(f"实例总数: {len(insts)} | 状态分布: {by_status}")

    if args.dry_run:
        for i in insts[:6]:
            print(f"  {i.InstanceId}  {i.Status}  {getattr(i, 'Image', '')[:70]}")
        return

    stopped = failed = 0
    for i in insts:
        try:
            if stop_instance(i.InstanceId):
                stopped += 1
            else:
                failed += 1
        except Exception as e:  # noqa: BLE001
            failed += 1
            if failed <= 3:
                print(f"  stop {i.InstanceId} 异常: {str(e)[:90]}")
    print(f"已停止 {stopped} | 失败/已停止 {failed} | 共 {len(insts)}")


if __name__ == "__main__":
    main()
