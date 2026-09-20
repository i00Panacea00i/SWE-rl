#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 13f35ad0915e70c2c299e2eb308968c86117132d -- test-data/unit/check-assert-type-fail.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-assert-type-fail.test b/test-data/unit/check-assert-type-fail.test
new file mode 100644
--- /dev/null
+++ b/test-data/unit/check-assert-type-fail.test
@@ -0,0 +1,28 @@
+[case testAssertTypeFail1]
+import typing
+import array as arr
+class array:
+    pass
+def f(si: arr.array[int]):
+    typing.assert_type(si, array) # E: Expression is of type "array.array[int]", not "__main__.array"
+[builtins fixtures/tuple.pyi]
+
+[case testAssertTypeFail2]
+import typing
+import array as arr
+class array:
+    class array:
+        i = 1
+def f(si: arr.array[int]):
+    typing.assert_type(si, array.array) # E: Expression is of type "array.array[int]", not "__main__.array.array"
+[builtins fixtures/tuple.pyi]
+
+[case testAssertTypeFail3]
+import typing
+import array as arr
+class array:
+    class array:
+        i = 1
+def f(si: arr.array[int]):
+    typing.assert_type(si, int) # E: Expression is of type "array[int]", not "int"
+[builtins fixtures/tuple.pyi]
\ No newline at end of file

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-assert-type-fail.test::testAssertTypeFail1 mypy/test/testcheck.py::TypeCheckSuite::check-assert-type-fail.test::testAssertTypeFail2 mypy/test/testcheck.py::TypeCheckSuite::check-assert-type-fail.test::testAssertTypeFail3
: '>>>>> End Test Output'
git checkout 13f35ad0915e70c2c299e2eb308968c86117132d -- test-data/unit/check-assert-type-fail.test 2>/dev/null || true
