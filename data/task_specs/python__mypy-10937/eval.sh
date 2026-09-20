#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 58c0a051b72731f093385cc7001b1f5c2abd2c18 -- test-data/unit/check-incremental.test test-data/unit/pep561.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-incremental.test b/test-data/unit/check-incremental.test
--- a/test-data/unit/check-incremental.test
+++ b/test-data/unit/check-incremental.test
@@ -5563,3 +5563,25 @@ class D:
 [out2]
 tmp/a.py:2: note: Revealed type is "builtins.list[builtins.int]"
 tmp/a.py:3: note: Revealed type is "builtins.list[builtins.str]"
+
+[case testIncrementalNamespacePackage1]
+# flags: --namespace-packages
+import m
+[file m.py]
+from foo.bar import x
+x + 0
+[file foo/bar.py]
+x = 0
+[rechecked]
+[stale]
+
+[case testIncrementalNamespacePackage2]
+# flags: --namespace-packages
+import m
+[file m.py]
+from foo import bar
+bar.x + 0
+[file foo/bar.py]
+x = 0
+[rechecked]
+[stale]
diff --git a/test-data/unit/pep561.test b/test-data/unit/pep561.test
--- a/test-data/unit/pep561.test
+++ b/test-data/unit/pep561.test
@@ -187,9 +187,8 @@ import a
 [out2]
 a.py:1: error: Unsupported operand types for + ("int" and "str")
 
--- Test for issue #9852, among others
-[case testTypedPkgNamespaceRegFromImportTwice-xfail]
-# pkgs: typedpkg, typedpkg_ns
+[case testTypedPkgNamespaceRegFromImportTwice]
+# pkgs: typedpkg_ns
 from typedpkg_ns import ns
 -- dummy should trigger a second iteration
 [file dummy.py.2]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testIncrementalNamespacePackage2 mypy/test/testcheck.py::TypeCheckSuite::testIncrementalNamespacePackage1
: '>>>>> End Test Output'
git checkout 58c0a051b72731f093385cc7001b1f5c2abd2c18 -- test-data/unit/check-incremental.test test-data/unit/pep561.test 2>/dev/null || true
