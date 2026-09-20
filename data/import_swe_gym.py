"""从 SWE-Gym 数据集导入候选训练题（P0-1 数据扩容 + P0-2 难度筛选）。

数据源: HuggingFace SWE-Gym/SWE-Gym（2,438 实例，11 个仓库，MIT 许可，
        与 SWE-bench 评测集零重叠——仓库集完全不同，天然无评测污染）。

筛选标准（锁定，回答"简单题目筛选"）:
  结构性（本脚本）:
  - F2P 数 ∈ [2, 8]      部分得分粒度（P0-2）+ 判分时长可控
  - gold patch ≤30 行、≤2 文件   小而聚焦的修复（降低定位难度）
  - P2P ≤ 50              判分时长可控（重跑套件规模上限）
  - problem_statement ≤4000 字符 issue 清晰聚焦
  - 镜像可得（xingyaoww/sweb.eval.x86_64.<iid 小写 __→_s_>）
  - 仓库速度分层          纯 Python 快测试仓库优先（RL 沙箱吞吐）
  经验性（后续基线 pilot，需 GPU）:
  - 基线通过率 ∈ [1/16, 10/16]  排除"解不动"（零奖励风险）与"全都会"（零梯度）

产物:
  data/task_specs/<iid>/{eval.sh, tests.json, task.yaml, test.patch, gold.patch}
  data/swe-gym-candidates.jsonl   全部结构筛选通过的候选（含镜像名与 tool_name）
  data/swe-gym-round1.jsonl       按优先级排序的前 N 个（用于镜像构建与双向验证）
"""
import argparse
import json
import shlex
import urllib.request
import concurrent.futures
from pathlib import Path

import pandas as pd

KIT = Path(__file__).resolve().parent.parent
PARQUET_URL = ("https://huggingface.co/api/datasets/SWE-Gym/SWE-Gym/"
               "parquet/default/train/0.parquet")

# 新仓库 → 源码模块名（判分前自检导入；与 sandbox/episode.py 的 map 保持一致）
REPO_MODULES = {
    "pandas-dev/pandas": "pandas", "Project-MONAI/MONAI": "monai",
    "getmoto/moto": "moto", "python/mypy": "mypy", "iterative/dvc": "dvc",
    "dask/dask": "dask", "modin-project/modin": "modin",
    "pydantic/pydantic": "pydantic", "conan-io/conan": "conan",
    "facebookresearch/hydra": "hydra", "bokeh/bokeh": "bokeh",
}
# 测试套件速度分层（0 最快；影响每 episode 沙箱耗时 → RL 吞吐）
REPO_SPEED_TIER = {
    "python/mypy": 0, "pydantic/pydantic": 0, "conan-io/conan": 0,
    "facebookresearch/hydra": 0, "getmoto/moto": 1, "iterative/dvc": 1,
    "bokeh/bokeh": 1, "pandas-dev/pandas": 2, "dask/dask": 2,
    "modin-project/modin": 2, "Project-MONAI/MONAI": 3,
}


def image_name(iid: str) -> str:
    return "xingyaoww/sweb.eval.x86_64." + iid.lower().replace("__", "_s_")


def check_image(iid: str) -> bool:
    url = f"https://hub.docker.com/v2/repositories/{image_name(iid)}/"
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=25) as r:
            return r.status == 200
    except Exception:
        return False


def patch_files(patch: str) -> list[str]:
    out = []
    for line in patch.splitlines():
        if line.startswith("diff --git a/"):
            out.append(line.split(" b/", 1)[0][len("diff --git a/"):])
    return out


def tool_name(iid: str, repo: str) -> str:
    short = repo.split("/")[1].lower()
    num = iid.rsplit("-", 1)[1]
    return f"swe-{short}-{num}"


def build_eval_sh(base: str, test_patch: str, test_ids: list[str]) -> str:
    files = patch_files(test_patch)
    checkout = " ".join(shlex.quote(f) for f in files)
    # 新建测试文件在 base 不存在，checkout 失败无害（脚本无 -e；判分沙箱为全新实例）
    reset = f"git checkout {base} -- {checkout} 2>/dev/null || true"
    marker = "EOF_SWEGYM"
    ids = " ".join(shlex.quote(t) for t in test_ids)
    return (
        "#!/bin/bash\n"
        "set -uxo pipefail\n"
        "source /opt/miniconda3/bin/activate\n"
        "conda activate testbed\n"
        "cd /testbed\n"
        "git config --global --add safe.directory /testbed\n"
        "git config --global http.sslVerify false\n"
        "git config --global user.email none@none.com\n"
        "git config --global user.name SWE-Gym\n"
        f"{reset}\n"
        f"git apply -v - <<'{marker}'\n"
        f"{test_patch}\n"
        f"{marker}\n"
        "python -m pip install -e . --no-deps\n"  # 占位：判分侧被替换为源码导入自检
        ": '>>>>> Start Test Output'\n"
        f"python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail {ids}\n"
        ": '>>>>> End Test Output'\n"
        f"{reset}\n"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--parquet", default="/tmp/swe-gym.parquet")
    ap.add_argument("--round1", type=int, default=120, help="首轮验证候选数")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    src = Path(args.parquet)
    if not src.exists():
        print(f"下载 {PARQUET_URL}")
        urllib.request.urlretrieve(PARQUET_URL, src)
    df = pd.read_parquet(src)
    print(f"数据集实例: {len(df)}（仓库 {df.repo.nunique()} 个）")

    df["f2p_n"] = df.FAIL_TO_PASS.apply(len)
    df["p2p_n"] = df.PASS_TO_PASS.apply(len)
    df["patch_lines"] = df.patch.str.count(r"\n\+") + df.patch.str.count(r"\n-")
    df["ps_len"] = df.problem_statement.str.len()
    df["files_n"] = df.patch.apply(lambda p: p.count("diff --git"))

    def _malformed(ids):
        # SWE-Gym 数据收集在特殊字符处截断过部分测试 ID（括号不闭合）
        return any(t.count("[") != t.count("]") or t.count("(") != t.count(")")
                   for t in ids)

    ok_ids = ~df.apply(
        lambda r: _malformed(list(r.FAIL_TO_PASS) + list(r.PASS_TO_PASS)), axis=1)
    cand = df[
        (df.f2p_n.between(2, 8)) & (df.patch_lines <= 30) & (df.files_n <= 2)
        & (df.p2p_n <= 50) & (df.ps_len <= 4000) & (df.repo.isin(REPO_MODULES)) & ok_ids
    ].copy()
    print(f"结构筛选后候选: {len(cand)}")

    # 镜像可得性
    with concurrent.futures.ThreadPoolExecutor(args.workers) as ex:
        avail = dict(zip(cand.instance_id, ex.map(check_image, cand.instance_id)))
    cand = cand[cand.instance_id.map(avail)]
    print(f"镜像可得: {len(cand)}")

    # 优先级：仓库速度层 → patch 行数 → F2P 落在 [3,8] 优先 → P2P 少
    cand["tier"] = cand.repo.map(REPO_SPEED_TIER)
    cand["f2p_pref"] = ~cand.f2p_n.between(3, 8)
    cand = cand.sort_values(["tier", "patch_lines", "f2p_pref", "p2p_n"])

    out = []
    for _, r in cand.iterrows():
        iid = r.instance_id
        out.append({
            "instance_id": iid, "repo": r.repo, "base_commit": r.base_commit,
            "version": str(r.version), "problem_statement": r.problem_statement,
            "f2p": list(r.FAIL_TO_PASS), "p2p": list(r.PASS_TO_PASS),
            "gold_patch": r.patch, "test_patch": r.test_patch,
            "image": image_name(iid), "tool_name": tool_name(iid, r.repo),
            "tier": int(r.tier), "source": "SWE-Gym",
        })

    # 写 task_specs（全部候选）
    for c in out:
        d = KIT / "data" / "task_specs" / c["instance_id"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "eval.sh").write_text(
            build_eval_sh(c["base_commit"], c["test_patch"], c["f2p"] + c["p2p"]))
        (d / "tests.json").write_text(json.dumps(
            {"FAIL_TO_PASS": c["f2p"], "PASS_TO_PASS": c["p2p"]}, indent=1))
        (d / "task.yaml").write_text(
            f"base_commit: {c['base_commit']}\n"
            f"instance_id: {c['instance_id']}\n"
            f"log_parser: parse_log_pytest\n"
            f"repo: {c['repo']}\n"
            f"version: '{c['version']}'\n")
        (d / "test.patch").write_text(c["test_patch"])
        (d / "gold.patch").write_text(c["gold_patch"])

    slim = [{k: v for k, v in c.items() if k not in ("problem_statement", "gold_patch", "test_patch")}
            for c in out]
    (KIT / "data" / "swe-gym-candidates.jsonl").write_text(
        "\n".join(json.dumps(c, ensure_ascii=False) for c in slim) + "\n")
    (KIT / "data" / "swe-gym-round1.jsonl").write_text(
        "\n".join(json.dumps(c, ensure_ascii=False) for c in slim[:args.round1]) + "\n")

    print(f"\n=== 导入完成 ===")
    print(f"候选总数: {len(out)}（task_specs 已生成）")
    print(f"round1 验证清单: {min(args.round1, len(out))} 题 → data/swe-gym-round1.jsonl")
    print("\nround1 仓库分布:")
    r1 = pd.Series([c["repo"] for c in out[:args.round1]])
    print(r1.value_counts().to_string())


if __name__ == "__main__":
    main()
