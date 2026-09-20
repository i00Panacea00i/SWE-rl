"""classify_operation 操作归类回归测试（结构化 tracing 的 kind 字段）。"""
import unittest

from sandbox.action_protocol import classify_operation


class TestClassifyOperation(unittest.TestCase):
    def test_test_commands(self):
        self.assertEqual(classify_operation(
            "python -m pytest -rA --no-header tests/unit/command/test_experiments.py::test_experiments_list"),
            "test")
        self.assertEqual(classify_operation("pytest -x tests/"), "test")
        self.assertEqual(classify_operation("python -m unittest discover"), "test")
        self.assertEqual(classify_operation("tox -e py39"), "test")

    def test_inspect_commands(self):
        self.assertEqual(classify_operation("cat /testbed/dvc/commands/experiments/__init__.py"), "inspect")
        self.assertEqual(classify_operation("grep -n 'def experiment_list' /testbed/dvc/commands/*.py"), "inspect")
        self.assertEqual(classify_operation("sed -n '1,80p' src/core.py"), "inspect")
        self.assertEqual(classify_operation("git diff HEAD~1"), "inspect")
        self.assertEqual(classify_operation("ls -la /testbed"), "inspect")
        self.assertEqual(classify_operation("python -c \"print(open('f.py').read())\""), "inspect")

    def test_edit_commands(self):
        self.assertEqual(classify_operation("sed -i 's/old/new/' /testbed/src/core.py"), "edit")
        self.assertEqual(classify_operation("echo 'x = 1' > /testbed/src/patch_target.py"), "edit")
        self.assertEqual(classify_operation("patch -p1 < fix.patch"), "edit")
        self.assertEqual(classify_operation("git apply /tmp/fix.diff"), "edit")
        self.assertEqual(classify_operation(
            "python -c \"open('/testbed/src/a.py','w').write('x')\""), "edit")
        self.assertEqual(classify_operation("python - <<'EOF'\nfrom pathlib import Path\nEOF"), "edit")

    def test_redirection_not_edit(self):
        # 2>/dev/null、2>&1、&>/dev/null 不是编辑
        self.assertEqual(classify_operation("python -c \"print(1)\" 2>/dev/null"), "inspect")
        self.assertEqual(classify_operation("./run.sh 2>&1 | tail -5"), "execute")

    def test_priority_edit_over_test(self):
        # 编辑+测试合并命令按 edit 计（是否跑过测试可由 executed_command 观察）
        self.assertEqual(classify_operation(
            "sed -i 's/a/b/' f.py && python -m pytest tests/test_f.py"), "edit")

    def test_execute_default(self):
        self.assertEqual(classify_operation("make build"), "execute")
        self.assertEqual(classify_operation("./scripts/repro.sh"), "execute")

    def test_empty(self):
        self.assertEqual(classify_operation(""), "empty")
        self.assertEqual(classify_operation("   "), "empty")

    def test_pytest_filename_not_false_positive(self):
        # `cat pytest.ini` 是查看，不是跑测试
        self.assertEqual(classify_operation("cat pytest.ini"), "inspect")


if __name__ == "__main__":
    unittest.main()
