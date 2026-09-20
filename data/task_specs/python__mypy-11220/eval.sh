#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout d37c2be0f7a2002a0a8c160622d937518f902cc7 -- test-data/unit/semanal-errors.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/semanal-errors.test b/test-data/unit/semanal-errors.test
--- a/test-data/unit/semanal-errors.test
+++ b/test-data/unit/semanal-errors.test
@@ -41,6 +41,49 @@ x = None # type: X
 [out]
 main:2: error: Name "X" is not defined
 
+[case testInvalidParamSpecType1]
+# flags: --python-version 3.10
+from typing import ParamSpec
+
+P = ParamSpec("P")
+
+class MyFunction(P):
+    ...
+
+a: MyFunction[int]
+[out]
+main:6: error: Invalid location for ParamSpec "P"
+main:6: note: You can use ParamSpec as the first argument to Callable, e.g., 'Callable[P, int]'
+main:9: error: "MyFunction" expects no type arguments, but 1 given
+
+[case testInvalidParamSpecType2]
+from typing_extensions import ParamSpec
+
+P = ParamSpec("P")
+
+class MyFunction(P):
+    ...
+
+a: MyFunction[int]
+[out]
+main:5: error: Invalid location for ParamSpec "P"
+main:5: note: You can use ParamSpec as the first argument to Callable, e.g., 'Callable[P, int]'
+main:8: error: "MyFunction" expects no type arguments, but 1 given
+
+[case testGenericParamSpec]
+# flags: --python-version 3.10
+from typing import Generic, TypeVar, Callable, ParamSpec
+
+T = TypeVar("T")
+P = ParamSpec("P")
+
+class X(Generic[T, P]):
+  f: Callable[P, int]
+  x: T
+[out]
+main:7: error: Free type variable expected in Generic[...]
+main:8: error: The first argument to Callable must be a list of types or "..."
+
 [case testInvalidGenericArg]
 from typing import TypeVar, Generic
 t = TypeVar('t')

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testsemanal.py::SemAnalErrorSuite::testInvalidParamSpecType1 mypy/test/testsemanal.py::SemAnalErrorSuite::testInvalidParamSpecType2 mypy/test/testsemanal.py::SemAnalErrorSuite::testGenericParamSpec mypy/test/testsemanal.py::SemAnalErrorSuite::testInvalidGenericArg
: '>>>>> End Test Output'
git checkout d37c2be0f7a2002a0a8c160622d937518f902cc7 -- test-data/unit/semanal-errors.test 2>/dev/null || true
