#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8b6d21373f44959d8aa194723e871e5468ad5c71 -- mypyc/test-data/run-functions.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/mypyc/test-data/run-functions.test b/mypyc/test-data/run-functions.test
--- a/mypyc/test-data/run-functions.test
+++ b/mypyc/test-data/run-functions.test
@@ -1256,3 +1256,33 @@ def foo(**kwargs: Unpack[Person]) -> None:
 foo(name='Jennifer', age=38)
 [out]
 Jennifer
+
+[case testNestedFunctionDunderDict312]
+import sys
+
+def foo() -> None:
+    def inner() -> str: return "bar"
+    print(inner.__dict__)  # type: ignore[attr-defined]
+    inner.__dict__.update({"x": 1})  # type: ignore[attr-defined]
+    print(inner.__dict__)  # type: ignore[attr-defined]
+    print(inner.x)  # type: ignore[attr-defined]
+
+if sys.version_info >= (3, 12):  # type: ignore
+    foo()
+[out]
+[out version>=3.12]
+{}
+{'x': 1}
+1
+
+[case testFunctoolsUpdateWrapper]
+import functools
+
+def bar() -> None:
+    def inner() -> str: return "bar"
+    functools.update_wrapper(inner, bar)  # type: ignore
+    print(inner.__dict__)  # type: ignore
+
+bar()
+[out]
+{'__module__': 'native', '__name__': 'bar', '__qualname__': 'bar', '__doc__': None, '__wrapped__': <built-in function bar>}

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypyc/test/test_run.py::TestRun::run-functions.test::testNestedFunctionDunderDict312 mypyc/test/test_run.py::TestRun::run-functions.test::testFunctoolsUpdateWrapper
: '>>>>> End Test Output'
git checkout 8b6d21373f44959d8aa194723e871e5468ad5c71 -- mypyc/test-data/run-functions.test 2>/dev/null || true
