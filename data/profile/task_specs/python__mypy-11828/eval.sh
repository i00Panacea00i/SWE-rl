#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout f96446ce2f99a86210b21d39c7aec4b13a8bfc66 -- test-data/unit/cmdline.pyproject.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/cmdline.pyproject.test b/test-data/unit/cmdline.pyproject.test
--- a/test-data/unit/cmdline.pyproject.test
+++ b/test-data/unit/cmdline.pyproject.test
@@ -80,3 +80,48 @@ def g(a: int) -> int:
 [out]
 pyproject.toml: toml config file contains [[tool.mypy.overrides]] sections with conflicting values. Module 'x' has two different values for 'disallow_untyped_defs'
 == Return code: 0
+
+[case testMultilineLiteralExcludePyprojectTOML]
+# cmd: mypy x
+[file pyproject.toml]
+\[tool.mypy]
+exclude = '''(?x)(
+    (^|/)[^/]*skipme_\.py$
+    |(^|/)_skipme[^/]*\.py$
+)'''
+[file x/__init__.py]
+i: int = 0
+[file x/_skipme_please.py]
+This isn't even syntatically valid!
+[file x/please_skipme_.py]
+Neither is this!
+
+[case testMultilineBasicExcludePyprojectTOML]
+# cmd: mypy x
+[file pyproject.toml]
+\[tool.mypy]
+exclude = """(?x)(
+    (^|/)[^/]*skipme_\\.py$
+    |(^|/)_skipme[^/]*\\.py$
+)"""
+[file x/__init__.py]
+i: int = 0
+[file x/_skipme_please.py]
+This isn't even syntatically valid!
+[file x/please_skipme_.py]
+Neither is this!
+
+[case testSequenceExcludePyprojectTOML]
+# cmd: mypy x
+[file pyproject.toml]
+\[tool.mypy]
+exclude = [
+    '(^|/)[^/]*skipme_\.py$',  # literal (no escaping)
+    "(^|/)_skipme[^/]*\\.py$",  # basic (backslash needs escaping)
+]
+[file x/__init__.py]
+i: int = 0
+[file x/_skipme_please.py]
+This isn't even syntatically valid!
+[file x/please_skipme_.py]
+Neither is this!

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcmdline.py::PythonCmdlineSuite::cmdline.pyproject.test::testMultilineLiteralExcludePyprojectTOML mypy/test/testcmdline.py::PythonCmdlineSuite::cmdline.pyproject.test::testMultilineBasicExcludePyprojectTOML mypy/test/testcmdline.py::PythonCmdlineSuite::cmdline.pyproject.test::testSequenceExcludePyprojectTOML
: '>>>>> End Test Output'
git checkout f96446ce2f99a86210b21d39c7aec4b13a8bfc66 -- test-data/unit/cmdline.pyproject.test 2>/dev/null || true
