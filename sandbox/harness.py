"""SWE-bench 沙箱执行 harness（协议核心）。

镜像 = 官方 swebench/sweb.eval 搬运（TCR swe-mirror），执行协议 = swe-bench-tasks 官方 eval.sh。

三种模式（均在 /testbed 上执行）：
- baseline: 直接跑 eval.sh            → 期望 F2P 全 FAIL、P2P 全 PASS（题目标定）
- golden:   reset → git apply 金标补丁 → 跑 eval.sh → 期望 F2P+P2P 全 PASS（数据自检）
- agent:    Agent 自由编辑后跑 eval.sh → 判定 resolved（RL reward 来源）

eval.sh 自身完成：checkout base 的测试文件 → git apply 测试补丁 → 跑测试命令，
测试输出夹在 '>>>>> Start/End Test Output' 标记之间，用 swebench 官方 log_parser 解析。
"""
from __future__ import annotations

import json
import os
import re
import time
from dataclasses import dataclass, field
from pathlib import Path

from swebench.harness import log_parsers
from swebench.types import TestSpec

KIT_ROOT = Path(__file__).resolve().parent.parent
START_MARKER = ">>>>> Start Test Output"
END_MARKER = ">>>>> End Test Output"


@dataclass
class Instance:
    """instances.jsonl 记录 + task_specs 官方协议的合并视图"""
    instance_id: str
    repo: str
    base_commit: str
    problem_statement: str
    image_ags: str
    image_env: str
    tool_name: str
    f2p: list
    p2p: list
    eval_sh: str
    gold_patch: str
    test_patch: str
    log_parser: str
    version: str
    # 镜像覆盖模式（docs/ags_image_override.md）：非空时沙箱走"通用工具+镜像覆盖"
    image_tcr: str = ""
    _spec: TestSpec = field(init=False, repr=False)

    def __post_init__(self):
        self._spec = TestSpec(
            instance_id=self.instance_id,
            image=self.image_ags,
            eval_script_list=[],
            repo=self.repo,
            version=self.version,
            FAIL_TO_PASS=self.f2p,
            PASS_TO_PASS=self.p2p,
            log_parser=self.log_parser,
        )


def load_instances(instance_ids: list[str] | None = None) -> list[Instance]:
    source = Path(os.environ.get("SWE_INSTANCES_FILE", str(KIT_ROOT / "data" / "instances.jsonl")))
    rows = [json.loads(l) for l in source.read_text().splitlines() if l.strip()]
    out = []
    for r in rows:
        if instance_ids and r["instance_id"] not in instance_ids:
            continue
        d = KIT_ROOT / "data" / "task_specs" / r["instance_id"]
        try:
            eval_sh = (d / "eval.sh").read_text()
            gold_patch = (d / "gold.patch").read_text()
            test_patch = (d / "test.patch").read_text()
            tests = json.loads((d / "tests.json").read_text())
            task = _parse_yaml_lite((d / "task.yaml").read_text())
        except FileNotFoundError as e:
            raise FileNotFoundError(f"task spec 不完整: {r['instance_id']}: {e}")
        out.append(Instance(
            instance_id=r["instance_id"],
            repo=r["repo"],
            base_commit=r["base_commit"],
            problem_statement=r["problem_statement"],
            image_ags=r["image_ags"],
            image_env=r["image_env"],
            tool_name=r["tool_name"],
            f2p=tests["FAIL_TO_PASS"],
            p2p=tests["PASS_TO_PASS"],
            eval_sh=eval_sh,
            gold_patch=gold_patch,
            test_patch=test_patch,
            log_parser=task["log_parser"],
            version=r.get("version", ""),
            image_tcr=r.get("image_tcr", ""),
        ))
    if instance_ids:
        got = {i.instance_id for i in out}
        missing = set(instance_ids) - got
        if missing:
            raise KeyError(f"instances.jsonl 中找不到: {sorted(missing)}")
    return out


def _parse_yaml_lite(text: str) -> dict:
    """task.yaml 只需 log_parser 等平铺标量，避免引入 yaml 依赖差异"""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^([a-z_]+):\s*'?(.*?)'?\s*$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


# ---------------------------------------------------------------- 沙箱命令构建

RESET_CMD = (
    "git config --global --add safe.directory /testbed && "
    "cd /testbed && git checkout {base} -- {files} && git clean -fdq"
)

APPLY_GOLD_CMD = (
    "git config --global --add safe.directory /testbed && "
    "cd /testbed && git apply -v /tmp/gold.patch"
)


def build_cmds(inst: Instance, mode: str) -> list[dict]:
    """返回按序执行的命令列表 [{name, cmd, timeout}]"""
    cmds = [{"name": "env_fingerprint",
             "cmd": "uname -a && cat /etc/os-release | head -2 && "
                    "/opt/miniconda3/envs/testbed/bin/python --version",
             "timeout": 30}]
    if mode == "baseline":
        cmds.append({"name": "eval_baseline", "cmd": "bash /tmp/eval.sh 2>&1",
                     "timeout": 1800})
    elif mode == "golden":
        # 注意：镜像内可能存在构建期的未提交修改（如 sphinx 官方 Dockerfile 对
        # tox.ini 的 sed 's/pytest/pytest -rA/'），禁止全树 reset（会还原它们）。
        # golden 必须在全新实例上执行：只应用金标补丁即可。
        cmds.append({"name": "apply_gold", "cmd": APPLY_GOLD_CMD, "timeout": 60})
        cmds.append({"name": "eval_golden", "cmd": "bash /tmp/eval.sh 2>&1",
                     "timeout": 1800})
    elif mode == "agent_grade":
        # Agent 改动已落盘，eval.sh 只重置测试文件并跑测试
        cmds.append({"name": "eval_agent", "cmd": "bash /tmp/eval.sh 2>&1",
                     "timeout": 1800})
    else:
        raise ValueError(mode)
    return cmds


def stage_files() -> dict[str, str]:
    """要预写入沙箱的文件: 路径 → 内容"""
    return {}


# ---------------------------------------------------------------- 解析与判分

def extract_test_log(stdout: str, stderr: str = "") -> str | None:
    """stdout+stderr 合并后截取 Start/End 标记之间的测试输出（与官方 get_logs_eval 一致）"""
    content = stdout + "\n" + stderr
    if START_MARKER not in content or END_MARKER not in content:
        return None
    return content.split(START_MARKER)[1].split(END_MARKER)[0]


def normalize_django_states(log: str, states: dict, required: list[str]) -> dict:
    """Recover exact test IDs from concatenated unittest/subTest output."""
    result = dict(states)
    mapping = {"ok": "PASSED", "OK": "PASSED", "FAIL": "FAILED",
               "ERROR": "ERROR", "skipped": "SKIPPED"}
    for test_id in required:
        escaped = re.escape(test_id)
        statuses = re.findall(escaped + r" \.\.\. (ok|OK|FAIL|ERROR|skipped)\b", log)
        if statuses:
            result[test_id] = mapping[statuses[-1]]
        failures = re.findall(r"^(FAIL|ERROR): " + escaped + r"(?:\s+\[[^\n]*\])?\s*$", log, re.M)
        if failures:
            result[test_id] = "ERROR" if "ERROR" in failures else "FAILED"
        if test_id not in result:
            short = test_id.split(" ", 1)[0]
            if sum(t.split(" ", 1)[0] == short for t in required) == 1 and short in states:
                result[test_id] = states[short]
    return result


def grade(inst: Instance, test_log: str | None) -> dict:
    """解析测试日志 → 逐用例状态 → F2P/P2P 判分"""
    if test_log is None:
        return {"status": "harness_error", "f2p_passed": [], "p2p_passed": [],
                "f2p_failed": list(inst.f2p), "p2p_failed": list(inst.p2p),
                "detail": "测试输出标记缺失"}
    parser = getattr(log_parsers, inst.log_parser, None)
    if parser is None:
        return {"status": "harness_error", "f2p_passed": [], "p2p_passed": [],
                "f2p_failed": list(inst.f2p), "p2p_failed": list(inst.p2p),
                "detail": f"未知 log_parser: {inst.log_parser}"}
    try:
        sm = parser(test_log, inst._spec)  # {test_id: PASSED/FAILED/ERROR...}
        if inst.log_parser == "parse_log_django":
            sm = normalize_django_states(test_log, sm, inst.f2p + inst.p2p)
    except Exception as e:
        return {"status": "harness_error", "f2p_passed": [], "p2p_passed": [],
                "f2p_failed": list(inst.f2p), "p2p_failed": list(inst.p2p),
                "detail": f"解析异常: {e}"}
    f2p_ok = [t for t in inst.f2p if sm.get(t) == "PASSED"]
    p2p_ok = [t for t in inst.p2p if sm.get(t) == "PASSED"]
    return {
        "status": "ok",
        "f2p_passed": f2p_ok, "f2p_failed": [t for t in inst.f2p if t not in f2p_ok],
        "p2p_passed": p2p_ok, "p2p_failed": [t for t in inst.p2p if t not in p2p_ok],
        "num_tests_parsed": len(sm),
    }


def compute_reward(inst: Instance, g: dict) -> float:
    """执行反馈奖励（验收口径）：fail→pass 测试数 / 总相关测试数。

    g 为 grade() 的返回值；harness_error 时为 0。
    注意 P2P 回归不直接扣分，但 resolved 判定仍要求 P2P 全过
    （与 swebench 官方 resolved 口径一致）。
    """
    if g.get("status") != "ok" or not inst.f2p:
        return 0.0
    return round(len(g["f2p_passed"]) / len(inst.f2p), 6)


def check_mode(mode: str, g: dict) -> tuple[bool, str]:
    """模式闸门：baseline 期望 F2P 全 FAIL；golden 期望全 PASS"""
    if g["status"] != "ok":
        return False, g["detail"]
    if mode == "baseline":
        if g["f2p_passed"]:
            return False, f"baseline 出现 F2P 通过（假阳性）: {g['f2p_passed'][:3]}"
        if g["p2p_failed"]:
            return False, f"P2P 回归: {g['p2p_failed'][:3]}"
        return True, "fail_as_expected"
    if mode == "golden":
        if g["f2p_failed"]:
            return False, f"F2P 未全过: {g['f2p_failed'][:3]}"
        if g["p2p_failed"]:
            return False, f"金标下 P2P 回归: {g['p2p_failed'][:3]}"
        return True, "pass"
    return True, "graded"


# ---------------------------------------------------------------- 证据记录

class Evidence:
    def __init__(self, run_id: str):
        self.run_id = run_id
        self.commands: list[dict] = []

    def record(self, cmd: str, exit_code, duration_ms: int,
               stdout: str, stderr: str, stdout_cap: int = 200_000):
        self.commands.append({
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "cmd": cmd, "exit_code": exit_code, "duration_ms": duration_ms,
            "stdout": stdout[:stdout_cap], "stderr": stderr[:50_000],
        })

    def save(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(
            {"run_id": self.run_id, "commands": self.commands},
            ensure_ascii=False, indent=1))
