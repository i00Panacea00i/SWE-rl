"""训练/评估前自检：确认 parquet 的沙箱路由（tool_name）与实例表一致。

AGS 是"一个沙箱工具 = 一个固定镜像"，路由错误只有在 episode 运行时才会暴露
（Untrusted sandbox route），会浪费整轮训练。这里在启动前快速失败。
"""
import sys

import pandas as pd

from sandbox.harness import load_instances


def main(paths):
    table = {i.instance_id: i.tool_name for i in load_instances()}
    failed = False
    for path in paths:
        for info in pd.read_parquet(path)["extra_info"]:
            iid, tool = info["instance_id"], info["tool_name"]
            if table.get(iid) != tool:
                print(f"路由不一致: {iid} parquet={tool} 实例表={table.get(iid)}")
                failed = True
    if failed:
        sys.exit(1)
    print("PREFLIGHT OK: 沙箱路由表一致")


if __name__ == "__main__":
    main(sys.argv[1:])
