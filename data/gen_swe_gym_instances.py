"""由 swe-gym-candidates.jsonl 生成 load_instances 兼容的实例清单。

image 字段记录公开源镜像（可入库）；AGS 工具经 tool_name 路由到 TCR 副本。
"""
import json
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
cands = [json.loads(l) for l in (KIT / "data" / "swe-gym-candidates.jsonl").read_text().splitlines() if l.strip()]

out = []
for c in cands:
    out.append({
        "instance_id": c["instance_id"],
        "repo": c["repo"],
        "base_commit": c["base_commit"],
        "problem_statement": "",  # 由 parquet 提示词生成阶段注入；验证不需要
        "image_ags": c["image"],
        "image_env": c["image"],
        "tool_name": c["tool_name"],
        "version": c["version"],
        "source": "SWE-Gym",
    })

# 合并 problem_statement
import pandas as pd
df = pd.read_parquet("/tmp/swe-gym.parquet").set_index("instance_id")
for o in out:
    o["problem_statement"] = df.loc[o["instance_id"], "problem_statement"]

path = KIT / "data" / "swe-gym-instances.jsonl"
path.write_text("\n".join(json.dumps(o, ensure_ascii=False) for o in out) + "\n")
print(f"生成 {len(out)} 个实例 → {path}")
