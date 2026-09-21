"""Trusted AGS episode driver; model commands never execute on the driver host."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import time
import uuid
from pathlib import Path, PurePosixPath

from e2b import Sandbox
from e2b.sandbox.commands.command_handle import CommandExitException
from unidiff import PatchSet

from sandbox.harness import Instance, compute_reward, extract_test_log, grade

GIT = ("git -c safe.directory=/testbed -c core.hooksPath=/dev/null "
       "-c core.fileMode=false")
MAX_PATCH_BYTES = 256_000
MAX_OUTPUT_BYTES = 32_768


def atomic_json(path: Path, record: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    with tmp.open("x", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False, allow_nan=False)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def protected_path(name: str) -> bool:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name:
        return True
    if any(p in {".git", ".github", "tests", "testing", "test", "__pycache__"} for p in path.parts):
        return True
    return path.name in {
        "conftest.py", "pytest.ini", "tox.ini", "setup.cfg", "pyproject.toml",
        "setup.py", "sitecustomize.py", "usercustomize.py", "Makefile",
    } or path.name.startswith("test_") or path.name.endswith("_test.py")


def check_patch(patch: str) -> list[str]:
    if len(patch.encode()) > MAX_PATCH_BYTES:
        raise ValueError("Patch exceeds size limit")
    if not patch.strip():
        return []
    if re.search(r"^(?:old|new) mode |^(?:new file|deleted file) mode (?!100644$|100755$)|"
                 r"^rename |^copy |^GIT binary patch|^Binary files", patch, re.M):
        raise ValueError("Binary, mode changes, renames and symlinks are not accepted")
    files = PatchSet(patch)
    if not files or len(files) > 30:
        raise ValueError("Invalid patch or too many changed files")
    names = []
    for f in files:
        if protected_path(f.path):
            raise ValueError(f"Protected or unsafe patch path: {f.path}")
        names.append(f.path)
    return names


def prepare_eval_script(inst: Instance) -> str:
    lines = inst.eval_sh.splitlines()
    starts = [i for i, line in enumerate(lines) if line == ": '>>>>> Start Test Output'"]
    ends = [i for i, line in enumerate(lines) if line == ": '>>>>> End Test Output'"]
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        raise ValueError("Unsupported eval script markers")
    start, end = starts[0], ends[0]
    modules = {"astropy/astropy": "astropy", "django/django": "django",
               "matplotlib/matplotlib": "matplotlib", "psf/requests": "requests",
               "pylint-dev/pylint": "pylint", "scikit-learn/scikit-learn": "sklearn",
               "sphinx-doc/sphinx": "sphinx", "sympy/sympy": "sympy",
               # SWE-Gym 扩容新增仓库（判分前源码导入自检用）
               "pandas-dev/pandas": "pandas", "Project-MONAI/MONAI": "monai",
               "getmoto/moto": "moto", "python/mypy": "mypy",
               "iterative/dvc": "dvc", "dask/dask": "dask",
               "modin-project/modin": "modin", "pydantic/pydantic": "pydantic",
               "conan-io/conan": "conan", "facebookresearch/hydra": "hydra",
               "bokeh/bokeh": "bokeh"}
    module = modules[inst.repo]
    check = ("import importlib,os; m=importlib.import_module(" + repr(module) + "); "
             "p=os.path.realpath(m.__file__); assert p.startswith('/testbed/'), p; "
             "print('SWE_SOURCE_IMPORT_OK', p)")
    prefix = []
    for line in lines[:start]:
        if line.startswith("git config "):
            continue
        if line.startswith("set -"):
            line = "set -eo pipefail"
        elif line.startswith("python -m pip install "):
            line = "python -c " + shlex.quote(check)
        prefix.append(line)
    test_commands = lines[start + 1:end]
    if not test_commands:
        raise ValueError("Empty test suite")
    return "\n".join(prefix + [
        "set +e", "printf '\\n>>>>> Start Test Output\\n'", "(",
        *test_commands, ")", "suite_rc=$?", "printf '\\n>>>>> End Test Output\\n'",
        "printf 'SWE_SUITE_EXIT=%s\\n' \"$suite_rc\"", "exit \"$suite_rc\"",
    ]) + "\n"


class EpisodeSession:
    def __init__(self, inst: Instance, directory: Path, timeout: int = 1800,
                 apply_test_patch: bool = False):
        self.inst = inst
        # rollout 侧置 True：把目标测试预置进沙箱，使 Agent 能跑测试获得执行反馈。
        # 在工作树快照之前应用，导出时只包含模型产生的差异。
        self.apply_test_patch = apply_test_patch
        self.directory = directory
        self.timeout = timeout
        self.sb = None
        self.commands = []
        self.sandbox_id = None
        self.fingerprint = ""
        self.tree = None
        self.sandbox_mode = ""

    def start(self):
        # 镜像覆盖模式：inst.image_tcr 存在时走"通用工具 + 镜像覆盖"（配额友好，
        # 见 docs/infrastructure/ags_image_override.md）；否则回退每题一工具的模板路径。
        image_tcr = getattr(self.inst, "image_tcr", "")
        if image_tcr:
            from sandbox.ags_instance import start_instance, stop_instance

            tool = os.environ.get("AGS_MULTI_TOOL", "swe-ags")
            instance_id = start_instance(image_tcr, tool_name=tool,
                                         timeout_s=self.timeout)
            try:
                self.sb = Sandbox.connect(instance_id, timeout=self.timeout)
            except Exception:
                stop_instance(instance_id)          # 连接失败不留下孤儿实例
                raise
            self.sandbox_mode = "image_override"
        else:
            self.sb = Sandbox.create(template=self.inst.tool_name, timeout=self.timeout)
            self.sandbox_mode = "template"
        self.sandbox_id = self.sb.sandbox_id
        result = self.run(f"cd /testbed && {GIT} rev-parse HEAD", 30, trusted=True)
        image_head = result[1].strip()
        base = self.inst.base_commit
        if result[0] != 0 or not re.fullmatch(r"[0-9a-f]{40}", base):
            raise RuntimeError(f"Cannot verify image HEAD for {self.inst.instance_id}")
        if image_head != base:
            # 官方 SWE-bench 镜像在 base_commit 之上有一个构建期提交（message 固定为
            # "SWE-bench"），承载环境准备改动（权限位、依赖 pin、sphinx tox.ini 的
            # -rA 等）。这些改动是评测所依赖的，禁止 reset 还原；此处只校验镜像确实
            # 是该实例的官方构建：base_commit 为祖先，且只多出这一个提交。
            probe = (
                "import subprocess\n"
                f"base={base!r}\n"
                "def g(*a):\n"
                # 沙箱内 Python 可能是 3.6（如 django-12286），不能用
                # capture_output/text（3.7+），改用 3.6 兼容写法。
                "    return subprocess.run(['git','-c','safe.directory=/testbed']+list(a),"
                "cwd='/testbed',stdout=subprocess.PIPE,stderr=subprocess.PIPE,"
                "universal_newlines=True)\n"
                "if g('merge-base','--is-ancestor',base,'HEAD').returncode!=0:\n"
                "    raise SystemExit('base_commit is not an ancestor of HEAD')\n"
                "print(g('log','-1','--format=%s','HEAD').stdout.strip())\n"
                "print(g('rev-list','--count',base+'..HEAD').stdout.strip())\n"
            )
            rc, probe_out, probe_err = self.run("python -c " + shlex.quote(probe), 60, trusted=True)
            lines = probe_out.strip().splitlines()
            if rc != 0 or len(lines) != 2 or lines[0] != "SWE-bench" or lines[1] != "1":
                raise RuntimeError(
                    f"Sandbox image is not the expected SWE-bench build for "
                    f"{self.inst.instance_id}: {(probe_out + probe_err).strip()[:200]}")
        _, self.fingerprint, _ = self.run("uname -a && cat /etc/os-release", 30, trusted=True)
        # 顺序很关键：先把目标测试预置进沙箱（rollout 侧），再对工作树做快照。
        # 这样快照已包含测试补丁，导出的候选补丁只含模型自己的改动，不会因为"触碰
        # 测试文件"被 check_patch 拒绝（此前该缺陷导致所有 episode 补丁恒为空）。
        if self.apply_test_patch and self.inst.test_patch.strip():
            self.sb.files.write("/tmp/swe-test.patch", self.inst.test_patch, user="root")
            code, out, err = self.run(f"{GIT} apply -v /tmp/swe-test.patch", 60, trusted=True)
            if code != 0:
                raise RuntimeError(
                    f"Cannot stage target tests for rollout: {(out + err)[-300:]}")
        index = f"/tmp/swe-index-{uuid.uuid4().hex}"
        cmd = (f"cd /testbed && cp .git/index {shlex.quote(index)} && "
               f"export GIT_INDEX_FILE={shlex.quote(index)} && {GIT} add -A && {GIT} write-tree")
        code, out, _ = self.run(cmd, 60, trusted=True)
        self.tree = out.strip()
        if code != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", self.tree):
            raise RuntimeError("Cannot snapshot pristine image working tree")
        return self

    def run(self, command: str, timeout: int = 60, trusted: bool = False):
        if self.sb is None:
            raise RuntimeError("Sandbox not started")
        if not trusted and (not command.strip() or len(command) > 12_000 or "\x00" in command):
            return 2, "", "Invalid or oversized command"
        inner = "export PATH=/opt/miniconda3/envs/testbed/bin:/opt/miniconda3/bin:$PATH; " + command
        drain = (
            "import sys\n"
            f"cap={MAX_OUTPUT_BYTES}; first=b''; tail=b''; total=0\n"
            "while True:\n"
            " chunk=sys.stdin.buffer.read(8192)\n"
            " if not chunk: break\n"
            " total+=len(chunk)\n"
            " first=(first+chunk)[:cap//4]\n"
            " tail=(tail+chunk)[-cap:]\n"
            "out=tail if total<=cap else first+b'\\n[output truncated; head and tail]\\n'+tail[-(cap*3//4):]\n"
            "sys.stdout.buffer.write(out)\n"
        )
        syntax = ""
        if not trusted:
            syntax = (f"check=$(bash -n -c {shlex.quote(command)} 2>&1); rc=$?; "
                      "if [ \"$rc\" -ne 0 ] || [ -n \"$check\" ]; then "
                      "printf '%s\\n' \"Incomplete/invalid shell action; not executed: $check\"; exit 2; fi; ")
        wrapped = (f"cd /testbed || exit 125; {syntax}"
                   f"timeout -k 5s {int(timeout)}s bash -lc {shlex.quote(inner)} 2>&1 | "
                   f"/opt/miniconda3/envs/testbed/bin/python -c {shlex.quote(drain)}; "
                   "codes=(\"${PIPESTATUS[@]}\"); "
                   "if [ \"${codes[1]}\" -ne 0 ]; then exit 125; fi; exit \"${codes[0]}\"")
        t0 = time.monotonic()
        try:
            r = self.sb.commands.run(wrapped, user="root", timeout=timeout + 20)
        except CommandExitException as exc:
            r = exc
        self.commands.append({
            "time": time.time(), "command": command, "exit_code": r.exit_code,
            "stdout": r.stdout, "stderr": r.stderr,
            "duration_s": round(time.monotonic() - t0, 3), "trusted": trusted,
        })
        return r.exit_code, r.stdout, r.stderr

    def export_patch(self) -> str:
        if not self.tree:
            raise RuntimeError("Missing image tree")
        index = f"/tmp/swe-export-{uuid.uuid4().hex}"
        cmd = (f"cd /testbed && cp .git/index {shlex.quote(index)} && "
               f"export GIT_INDEX_FILE={shlex.quote(index)} && {GIT} add -A && "
               f"{GIT} diff --cached --no-ext-diff --no-textconv --binary {self.tree}")
        # Export exceeds the observation cap only in the trusted driver path.
        try:
            r = self.sb.commands.run(cmd, user="root", timeout=60)
        except CommandExitException as exc:
            raise RuntimeError("Could not export candidate patch") from exc
        check_patch(r.stdout)
        return r.stdout

    def changed_files(self) -> list[str]:
        """相对原始工作树快照发生变化的文件（空列表 = 模型未做任何改动）。

        用于拒绝"未编辑就提交"的空补丁 episode。测试补丁已在快照之前应用，
        因此不会被计入。
        """
        if self.tree is None:
            raise RuntimeError("Session not started")
        index = f"/tmp/swe-check-{uuid.uuid4().hex}"
        cmd = (f"cd /testbed && cp .git/index {shlex.quote(index)} && "
               f"export GIT_INDEX_FILE={shlex.quote(index)} && {GIT} add -A && "
               f"{GIT} diff --cached --name-only {self.tree}")
        code, out, _ = self.run(cmd, 60, trusted=True)
        if code != 0:
            raise RuntimeError("Cannot inspect working tree changes")
        return [line.strip() for line in out.splitlines() if line.strip()]

    def close(self):
        cleanup_error = None
        if self.sb is not None:
            try:
                self.sb.kill()
            except Exception as exc:
                cleanup_error = type(exc).__name__
            self.sb = None
        atomic_json(self.directory / "execution.json", {
            "instance_id": self.inst.instance_id, "sandbox_id": self.sandbox_id,
            "fingerprint": self.fingerprint, "commands": self.commands,
            "cleanup_error": cleanup_error,
        })
        if cleanup_error:
            raise RuntimeError(f"Sandbox cleanup failed: {self.sandbox_id} ({cleanup_error})")


def evaluate_patch(inst: Instance, patch: str, directory: Path, timeout: int = 1800,
                   validation_gold: bool = False) -> dict:
    """Score in a fresh sandbox. The model never sees gold.patch or this scorer."""
    if not validation_gold:
        check_patch(patch)
    session = EpisodeSession(inst, directory, timeout + 300)
    result = None
    try:
        session.start()
        if patch.strip():
            session.sb.files.write("/tmp/candidate.patch", patch, user="root")
            code, out, err = session.run(
                f"{GIT} apply --check /tmp/candidate.patch && {GIT} apply /tmp/candidate.patch",
                60, trusted=True)
            if code != 0:
                raise RuntimeError(f"Patch application failed: {(out + err)[-500:]}")
        session.sb.files.write("/tmp/swe-eval.sh", prepare_eval_script(inst), user="root")
        # Preserve the complete test log remotely; model-controlled output is not used as reward.
        cmd = ("GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=/testbed "
               f"timeout -k 10s {int(timeout)}s bash /tmp/swe-eval.sh > /tmp/swe-eval.log 2>&1")
        try:
            r = session.sb.commands.run(cmd, user="root", timeout=timeout + 30)
        except CommandExitException as exc:
            r = exc
        raw = session.sb.files.read("/tmp/swe-eval.log", user="root")
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "test.log").write_text(raw, encoding="utf-8")
        from swebench.harness import log_parsers
        log = extract_test_log(raw)
        if not raw.strip() or r.exit_code not in (0, 1, 2):
            raise RuntimeError(f"Infrastructure/timeout failure: exit={r.exit_code}; log={directory / 'test.log'}")
        parser = getattr(log_parsers, inst.log_parser)
        states = parser(log, inst._spec) if log is not None else {}
        required = inst.f2p + inst.p2p
        if inst.log_parser == "parse_log_django":
            from sandbox.harness import normalize_django_states
            states = normalize_django_states(log or "", states, required)
        missing = [t for t in required if t not in states]
        complete = (log is not None and
                    re.search(rf"^SWE_SUITE_EXIT={r.exit_code}\s*$", raw, re.M) is not None)
        failure_kind = None
        if missing or not complete:
            # 候选补丁引发的失败有两类：
            # 1) 语法/导入/收集错误（下方正则）；
            # 2) 框架级启动失败：测试进程在运行任何用例前崩溃——如 Django 的
            #    SystemCheckError（模型改坏 check 函数，runtests 在收集/系统检查
            #    阶段即失败）。形态是：标记完整、日志含 Traceback、但没有任何
            #    目标用例出现在输出中。两类都必须记 0 分而不是抛异常（抛异常会
            #    丢失样本并触发流水线 fatal 停机）。
            nothing_ran = log is not None and not any(t in log for t in required)
            has_traceback = "Traceback (most recent call last)" in raw
            candidate_error = bool(re.search(
                r"SyntaxError|IndentationError|ImportError|ModuleNotFoundError|"
                r"errors? during collection|^ERROR collecting|^ERROR .*\.py", raw, re.M)) or (
                nothing_ran and has_traceback)
            if not patch.strip() or validation_gold or not candidate_error or r.exit_code == 0:
                raise RuntimeError(f"Incomplete evaluation, not a reward: exit={r.exit_code}; missing={missing[:5]}")
            # A fresh unpatched control must execute successfully before blaming the candidate.
            session.close()
            control = evaluate_patch(inst, "", directory / "baseline-control", timeout)
            if not control.get("suite_collected"):
                raise RuntimeError("Baseline control also failed; refusing a candidate reward")
            failure_kind = "candidate_collection_or_import_error"
        suite_collected = not missing and complete
        g = {
            "status": "ok", "num_tests_parsed": len(states),
            "f2p_passed": [t for t in inst.f2p if states.get(t) == "PASSED"],
            "f2p_failed": [t for t in inst.f2p if states.get(t) != "PASSED"],
            "p2p_passed": [t for t in inst.p2p if states.get(t) == "PASSED"],
            "p2p_failed": [t for t in inst.p2p if states.get(t) != "PASSED"],
        }
        result = {
            "instance_id": inst.instance_id, "sandbox_id": session.sandbox_id,
            "reward": compute_reward(inst, g),
            "resolved": suite_collected and bool(inst.f2p) and not g["f2p_failed"] and not g["p2p_failed"],
            "grade": g, "failure_kind": failure_kind,
            "test_states": {t: states.get(t, "NOT_RUN") for t in required},
            "suite_exit": r.exit_code, "suite_collected": suite_collected,
            "test_log": str(directory / "test.log"),
            "patch_sha256": hashlib.sha256(patch.encode()).hexdigest(),
        }
        atomic_json(directory / "result.json", result)
        return result
    finally:
        session.close()
