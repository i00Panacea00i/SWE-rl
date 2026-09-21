#!/usr/bin/env python3
"""AGS 沙箱配额探针：尝试创建一个最小沙箱，成功即立刻停止。

用途：评估分批前的准入检查。AGS 沙箱实例配额上限 100，且 STOPPED 实例
在自身 TTL 到期前仍占配额（平台无删除 API）。本探针返回：
  退出码 0 = 配额可用；1 = 配额繁忙（调用方应等待重试）
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "sandbox"))

from ags_instance import start_instance, stop_instance  # noqa: E402

PROBE_IMAGE = ("registry.example.com/swe-mirror/swe-ags:"
               "iterative_s_dvc-4623")


def main() -> int:
    iid = None
    try:
        iid = start_instance(PROBE_IMAGE, tool_name="swe-ags", timeout_s=300)
        print(f"QUOTA_OK {iid}", flush=True)
        return 0
    except Exception as e:  # noqa: BLE001
        print(f"QUOTA_BUSY {str(e)[:140]}", flush=True)
        return 1
    finally:
        if iid:
            try:
                stop_instance(iid)
            except Exception:  # noqa: BLE001
                pass


if __name__ == "__main__":
    sys.exit(main())
