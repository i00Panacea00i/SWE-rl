import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from sandbox.episode import (EpisodeSession, atomic_json, check_patch,
                             evaluate_patch, prepare_eval_script)
from sandbox.harness import load_instances
from verl_plugin.reward import compute_score


class EpisodeTests(unittest.TestCase):
    def test_patch_guard(self):
        template = 'diff --git a/{0} b/{0}\n--- a/{0}\n+++ b/{0}\n@@ -1 +1 @@\n-old\n+new\n'
        self.assertEqual(check_patch(template.format('package/module.py')), ['package/module.py'])
        for name in ['../x.py', 'tests/test_a.py', '.git/config', 'conftest.py', 'setup.py']:
            with self.assertRaises(ValueError):
                check_patch(template.format(name))
        with self.assertRaises(ValueError):
            check_patch('diff --git a/link b/link\nnew file mode 120000\n')

    def test_eval_wrappers_parse_and_preserve_commands(self):
        for inst in load_instances():
            script = prepare_eval_script(inst)
            result = subprocess.run(['bash', '-n'], input=script, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('git config --global', script)
            self.assertIn('SWE_SUITE_EXIT=', script)
            self.assertIn('git apply -v -', script)
            self.assertNotIn(inst.gold_patch, script)

    def test_scoring_requires_driver_result(self):
        with self.assertRaises(ValueError):
            compute_score('swe-bench-ags', 'PASSED SUBMIT', 'task')
        result = {'instance_id': 'task', 'reward': 0.5, 'resolved': False}
        self.assertEqual(compute_score('swe-bench-ags', '', 'task', {'swe_evaluation': result}),
                         {'score': 0.5, 'acc': 0.0})

    def test_cleanup_persists_evidence_on_failure(self):
        inst = load_instances(['django__django-10939'])[0]
        with tempfile.TemporaryDirectory() as tmp:
            session = EpisodeSession(inst, Path(tmp))
            with patch('sandbox.episode.Sandbox.create', side_effect=RuntimeError('create failed')):
                with self.assertRaises(RuntimeError):
                    session.start()
            session.close()
            self.assertTrue((Path(tmp) / 'execution.json').exists())

    def test_atomic_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'sub/result.json'
            atomic_json(p, {'ok': True})
            self.assertEqual(len(list(p.parent.iterdir())), 1)


class _Resp:
    def __init__(self, exit_code, stdout=""):
        self.exit_code = exit_code
        self.stdout = stdout


class _FakeFiles:
    def __init__(self, store):
        self.store = store

    def write(self, path, content, user=None):
        self.store[path] = content

    def read(self, path, user=None):
        return self.store[path]


class _FakeSession:
    """最小替身：只回放给定判分日志与退出码。"""

    def __init__(self, eval_log, exit_code):
        self.sandbox_id = "fake-sandbox"
        self.tree = "0" * 40
        self.store = {"/tmp/swe-eval.log": eval_log}
        sb = type("SB", (), {})()
        sb.files = _FakeFiles(self.store)
        sb.commands = type("C", (), {
            "run": lambda _s, cmd, user=None, timeout=None: _Resp(exit_code)})()
        self.sb = sb

    def start(self):
        return self

    def run(self, command, timeout=60, trusted=False):
        return 0, "", ""

    def close(self):
        pass


class JudgeRobustnessTests(unittest.TestCase):
    """模型产出的坏补丁必须记 0 分，而不是让 episode 崩溃丢失样本。"""

    PATCH = 'diff --git a/pkg/m.py b/pkg/m.py\n--- a/pkg/m.py\n+++ b/pkg/m.py\n@@ -1 +1 @@\n-a\n+b\n'

    def _run(self, eval_log, exit_code, control_ok=True, validation_gold=False):
        inst = load_instances(['astropy__astropy-12907'])[0]
        baseline = (">>>>> Start Test Output\n" +
                    "\n".join("FAILED " + t for t in inst.f2p) + "\n" +
                    "\n".join("PASSED " + t for t in inst.p2p) +
                    "\n>>>>> End Test Output\nSWE_SUITE_EXIT=1\n")
        with tempfile.TemporaryDirectory() as tmp:
            sessions = [_FakeSession(eval_log, exit_code),
                        _FakeSession(baseline if control_ok else 'environment broken', 1)]
            with patch('sandbox.episode.EpisodeSession', side_effect=sessions):
                return evaluate_patch(inst, self.PATCH, Path(tmp), validation_gold=validation_gold)

    def test_collection_error_scores_zero_after_baseline_control(self):
        log = (">>>>> Start Test Output\nE IndentationError\n"
               "ERROR astropy/modeling/tests/test_separable.py\n"
               "Interrupted: 2 errors during collection\n"
               ">>>>> End Test Output\nSWE_SUITE_EXIT=2\n")
        res = self._run(log, 2)
        self.assertEqual(res['reward'], 0.0)
        self.assertFalse(res['resolved'])
        self.assertFalse(res['suite_collected'])
        self.assertEqual(res['failure_kind'], 'candidate_collection_or_import_error')
        self.assertTrue(all(v == 'NOT_RUN' for v in res['test_states'].values()))
        with self.assertRaises(RuntimeError):
            self._run(log, 2, control_ok=False)
        with self.assertRaises(RuntimeError):
            self._run(log, 2, validation_gold=True)

    def test_prefix_and_timeout_failures_are_not_rewards(self):
        for log, code in [('environment missing', 1), ('Traceback\nAssertionError: bad', 1),
                          ('>>>>> Start Test Output\npartial output', 124), ('', 1)]:
            with self.subTest(code=code, log=log):
                with self.assertRaises(RuntimeError):
                    self._run(log, code)

    def test_import_error_requires_successful_control(self):
        result = self._run('Traceback\nImportError: candidate import broken', 1)
        self.assertEqual(result['reward'], 0.0)
        with self.assertRaises(RuntimeError):
            self._run('Traceback\nImportError: candidate import broken', 1, control_ok=False)

    def test_framework_check_error_scores_zero_after_baseline_control(self):
        # Django SystemCheckError：模型改坏 check 函数导致 runtests 在系统检查
        # 阶段崩溃，测试从未运行（标记完整、有 Traceback、无任何目标用例输出）。
        # 必须记 0 分而非抛异常（否则触发流水线 fatal 停机，见 fullbatch-v3 事故）。
        log = (">>>>> Start Test Output\n"
               "Traceback (most recent call last):\n"
               "  File \"/testbed/django/test/runner.py\", line 698, in run_tests\n"
               "    self.run_checks()\n"
               "django.core.management.base.SystemCheckError: SystemCheckError: "
               "System check identified some issues:\n"
               "ERRORS:\n"
               "?: (translation.E004) You have provided a value for the LANGUAGE_CODE "
               "setting that is not in the LANGUAGES setting.\n"
               ">>>>> End Test Output\nSWE_SUITE_EXIT=1\n")
        res = self._run(log, 1)
        self.assertEqual(res['reward'], 0.0)
        self.assertFalse(res['resolved'])
        self.assertFalse(res['suite_collected'])
        self.assertEqual(res['failure_kind'], 'candidate_collection_or_import_error')
        with self.assertRaises(RuntimeError):
            self._run(log, 1, control_ok=False)


if __name__ == '__main__':
    unittest.main()