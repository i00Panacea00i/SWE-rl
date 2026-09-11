"""本地 Docker 冒烟：用与 AGS 完全相同的 harness 协议验证镜像 + eval.sh。

用法：
    python sandbox/local_smoke.py --instances django__django-10939,psf__requests-1327 [--modes baseline,golden]
先拉镜像：docker pull $(image_ags)
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import (Instance, build_cmds, check_mode, extract_test_log,  # noqa: E402
                     grade, load_instances)


def docker_run_detached(image: str, name: str) -> str:
    subprocess.run(["docker", "rm", "-f", name], capture_output=True)
    r = subprocess.run(
        ["docker", "run", "-d", "--name", name, "--entrypoint", "",
         image, "sleep", "infinity"],
        capture_output=True, text=True, check=True)
    return r.stdout.strip()


def docker_exec(name: str, cmd: str, timeout: int) -> tuple[int, str, str]:
    r = subprocess.run(
        ["docker", "exec", name, "bash", "-lc", cmd],
        capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout, r.stderr


def docker_cp_write(name: str, dst: str, content: str):
    p = Path("/tmp") / f"smoke_{time.time_ns()}"
    p.write_text(content)
    subprocess.run(["docker", "cp", str(p), f"{name}:{dst}"], check=True,
                   capture_output=True)
    p.unlink()


def run_instance(inst: Instance, modes: list[str]) -> dict:
    print(f"\n=== {inst.instance_id} ({', '.join(modes)}) ===")
    results = {}
    # 每个模式使用全新容器：镜像内可能存在构建期未提交修改，禁止跨模式复用
    for mode in modes:
        cname = ("smoke-" + inst.instance_id.replace("__", "-").replace("/", "-")
                 + "-" + mode)
        docker_run_detached(inst.image_ags, cname)
        t0 = time.time()
        g = {"status": "harness_error", "detail": "not run"}
        try:
            docker_cp_write(cname, "/tmp/eval.sh", inst.eval_sh)
            docker_cp_write(cname, "/tmp/gold.patch", inst.gold_patch)
            for c in build_cmds(inst, mode):
                code, out, err = docker_exec(cname, c["cmd"], c["timeout"])
                if not c["name"].startswith("eval_") and code != 0:
                    g = {"status": "harness_error",
                         "detail": f"命令 {c['name']} 失败 exit={code}: {err[-300:]}"}
                    break
                log = extract_test_log(out, err)
                if c["name"].startswith("eval_"):
                    g = grade(inst, log)
            ok, why = check_mode(mode, g)
        finally:
            subprocess.run(["docker", "rm", "-f", cname], capture_output=True)
        results[mode] = {"ok": ok, "why": why,
                         "f2p_pass": len(g.get("f2p_passed", [])),
                         "f2p_total": len(inst.f2p),
                         "p2p_pass": len(g.get("p2p_passed", [])),
                         "p2p_total": len(inst.p2p),
                         "secs": round(time.time() - t0, 1)}
        print(f"  [{mode}] {'PASS' if ok else 'FAIL'} {results[mode]}")
        if not ok and g.get("status") == "harness_error":
            print(f"    detail: {g['detail']}")
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--instances", default="django__django-10939,psf__requests-1327")
    ap.add_argument("--modes", default="baseline,golden")
    ap.add_argument("--output", default="artifacts/local_smoke.json")
    args = ap.parse_args()

    ids = [i for i in args.instances.split(",") if i]
    if ids == ["all"]:
        ids = None  # 全部实例
    insts = load_instances(ids)
    out = {}
    for inst in insts:
        out[inst.instance_id] = run_instance(inst, args.modes.split(","))

    p = Path(__file__).resolve().parent.parent / args.output
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    all_ok = all(all(m["ok"] for m in r.values()) for r in out.values())
    print(f"\n结果已写 {p}；总体: {'ALL PASS' if all_ok else 'HAS FAILURES'}")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
