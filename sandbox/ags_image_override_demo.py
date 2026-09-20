"""AGS 单工具多镜像（Image Override）全闭环验证脚本。

用途：在**同一个通用沙箱工具**上，用镜像覆盖拉起不同题目的环境，
经 e2b connect 执行命令验证，然后 kill 清理。配套文档：
docs/ags_image_override.md

用法：
  set -a && source .env && set +a
  venv/bin/python sandbox/ags_image_override_demo.py \
      --tool swe-ags \
      --image-tag python_s_mypy-5617

前置：
  - 凭证：环境变量 TENCENTCLOUD_REFRESH_TOKEN/OPEN_ID 或 ~/.tccli/default.credential
  - E2B_API_KEY / E2B_DOMAIN 已设置（e2b connect 用）
  - 目标镜像已预热（CreatePreCacheImageTask），否则启动更慢
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # 允许独立运行


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tool", default="swe-ags", help="通用沙箱工具名")
    ap.add_argument("--image-tag", default="python_s_mypy-5617",
                    help="覆盖镜像 tag（instance_id 小写、__→_s_）或完整镜像地址")
    ap.add_argument("--command", default=(
        "cd /testbed && git log --oneline -1 && "
        "/opt/miniconda3/envs/testbed/bin/python -c \"print('env OK')\""))
    args = ap.parse_args()

    from sandbox.ags_instance import DEFAULT_IMAGE_PREFIX, start_instance, stop_instance

    image = args.image_tag if "/" in args.image_tag else f"{DEFAULT_IMAGE_PREFIX}:{args.image_tag}"
    t0 = time.time()
    iid = start_instance(image, tool_name=args.tool, timeout_s=900)
    print(f"1) 创建+就绪: {iid} ({time.time()-t0:.1f}s) | ...{image[-50:]}")

    from e2b import Sandbox
    sbx = Sandbox.connect(iid, timeout=1800)
    r = sbx.commands.run(args.command, user="root")
    print(f"2) 执行输出:\n{r.stdout.strip()[:300]}")
    sbx.kill()
    print(f"3) kill 完成（总 {time.time()-t0:.1f}s）")

    stop_instance(iid)
    print("4) 清理完成 — 全闭环 ✓")


if __name__ == "__main__":
    os.environ.setdefault("VLLM_LOGGING_LEVEL", "WARNING")
    main()
