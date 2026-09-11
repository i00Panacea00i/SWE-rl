"""tracing 冒烟：脚本化 Agent 在沙箱中完成 ≥3 步交互并产出 episode JSONL。

对齐 README §6 的 tracing ↔ verl DataProto 映射：
  steps[].action      → response_ids (mask=1，算 loss)
  steps[].observation → response_ids (mask=0，不算 loss)
  final.reward        → rm_scores

runtime=docker  现在即可跑（本地镜像）
runtime=ags     工具就绪后跑（template=tool_name）

用法：
  venv/bin/python sandbox/agent_smoke.py --runtime docker --instance django__django-10939
  venv/bin/python sandbox/agent_smoke.py --runtime ags   --instance django__django-10939
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import (compute_reward, extract_test_log, grade,  # noqa: E402
                     load_instances)

KIT_ROOT = Path(__file__).resolve().parent.parent


class DockerSandbox:
    def __init__(self, image: str):
        self.name = "agent-" + f"{time.time_ns()}"[-9:]
        subprocess.run(["docker", "run", "-d", "--name", self.name,
                        "--entrypoint", "", image, "sleep", "infinity"],
                       capture_output=True, check=True)

    def run(self, cmd: str, timeout: int = 600):
        r = subprocess.run(["docker", "exec", self.name, "bash", "-lc", cmd],
                           capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr

    def write(self, path: str, content: str):
        p = Path("/tmp") / f"aw_{time.time_ns()}"
        p.write_text(content)
        subprocess.run(["docker", "cp", str(p), f"{self.name}:{path}"],
                       check=True, capture_output=True)
        p.unlink()

    def kill(self):
        subprocess.run(["docker", "rm", "-f", self.name], capture_output=True)


class AgsSandbox:
    def __init__(self, template: str, timeout: int = 3600):
        from e2b_code_interpreter import Sandbox
        from e2b.sandbox.commands.command_handle import CommandExitException
        self._Exit = CommandExitException
        self.sb = Sandbox.create(template=template, timeout=timeout)

    def run(self, cmd: str, timeout: int = 600):
        try:
            r = self.sb.commands.run(cmd, user="root", timeout=timeout)
            return r.exit_code, r.stdout, r.stderr
        except self._Exit as e:  # exit≠0 是正常业务码
            return e.exit_code, e.stdout, e.stderr

    def write(self, path: str, content: str):
        self.sb.files.write(path, content)

    def kill(self):
        try:
            self.sb.kill()
        except Exception:
            pass


# 脚本化 3 步 Agent（模拟 SWE-agent 的 bash 交互回路，确定性动作）
def scripted_steps(inst) -> list[dict]:
    # 从金标补丁取第一个被改文件，让步骤对任意仓库通用
    m = re.search(r"^\+\+\+ b/(.+)$", inst.gold_patch, re.M)
    target = m.group(1) if m else "."
    return [
        {"step": 1, "thought": "定位问题相关文件",
         "action": "cd /testbed && ls && git log --oneline -1"},
        {"step": 2, "thought": f"查看疑似问题代码 {target}",
         "action": f"cd /testbed && head -40 {target}"},
        {"step": 3, "thought": "实施修复（模拟 Agent 编辑）",
         "action": "git config --global --add safe.directory /testbed && "
                   "cd /testbed && git apply /tmp/gold.patch && echo PATCH_APPLIED"},
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runtime", choices=["docker", "ags"], default="docker")
    ap.add_argument("--instance", default="django__django-10939")
    ap.add_argument("--max-steps", type=int, default=8)
    ap.add_argument("--output", default="artifacts/traces")
    args = ap.parse_args()

    inst = load_instances([args.instance])[0]
    sb = (DockerSandbox(inst.image_ags) if args.runtime == "docker"
          else AgsSandbox(inst.tool_name))

    episode = {
        "instance_id": inst.instance_id,
        "runtime": args.runtime,
        "tool_name": inst.tool_name,
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "steps": [],
        "final": None,
    }
    try:
        sb.write("/tmp/eval.sh", inst.eval_sh)
        sb.write("/tmp/gold.patch", inst.gold_patch)

        code, out, _ = sb.run("uname -a && /opt/miniconda3/envs/testbed/bin/python --version", 30)
        episode["env_fingerprint"] = out.strip()[:200]

        for s in scripted_steps(inst)[:args.max_steps]:
            t0 = time.time()
            code, out, err = sb.run(s["action"], 300)
            obs = (out if out else "") + (("\n[stderr] " + err) if err else "")
            episode["steps"].append({
                "step": s["step"], "thought": s["thought"],
                "action": s["action"],          # → response_ids (mask=1)
                "observation": obs[-4000:],      # → response_ids (mask=0)
                "reward": 0.0,                   # → rm_scores（非终止步为 0）
                "done": False,                   # → episode 终止标志
                "exit_code": code,
                "duration_ms": int((time.time() - t0) * 1000),
            })
            print(f"  step{s['step']} exit={code} obs={len(obs)}B "
                  f"({episode['steps'][-1]['duration_ms']}ms)")

        # 终局判定：agent_grade 模式（eval.sh 只重置测试文件并跑测试）
        code, out, err = sb.run("bash /tmp/eval.sh 2>&1", 1800)
        log = extract_test_log(out, err)
        g = grade(inst, log)
        reward = compute_reward(inst, g)   # fail→pass 测试数 / F2P 总数
        resolved = (g["status"] == "ok" and not g["f2p_failed"]
                    and not g["p2p_failed"])
        # 终止步回填 reward/done（对齐验收：每步含 (action, observation, reward, done)）
        if episode["steps"]:
            episode["steps"][-1]["reward"] = reward
            episode["steps"][-1]["done"] = True
        episode["final"] = {                      # → rm_scores 汇总
            "reward": reward,
            "resolved": resolved,
            "f2p_pass": len(g.get("f2p_passed", [])), "f2p_total": len(inst.f2p),
            "p2p_pass": len(g.get("p2p_passed", [])), "p2p_total": len(inst.p2p),
            "num_steps": len(episode["steps"]),
        }
    finally:
        sb.kill()

    outdir = KIT_ROOT / args.output / inst.instance_id
    outdir.mkdir(parents=True, exist_ok=True)
    fp = outdir / f"episode-{time.strftime('%Y%m%d-%H%M%S')}.jsonl"
    fp.write_text(json.dumps(episode, ensure_ascii=False) + "\n")
    print(f"\nepisode → {fp}")
    print(f"final: {episode['final']}")
    assert len(episode["steps"]) >= 3, "验收要求 ≥3 步 tracing"
    sys.exit(0 if episode["final"]["resolved"] else 1)


if __name__ == "__main__":
    main()
