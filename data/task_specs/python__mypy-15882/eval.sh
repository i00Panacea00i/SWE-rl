#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 14418bc3d2c38b9ea776da6029e9d9dc6650b7ea -- test-data/unit/check-python310.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-python310.test b/test-data/unit/check-python310.test
--- a/test-data/unit/check-python310.test
+++ b/test-data/unit/check-python310.test
@@ -1372,7 +1372,7 @@ match m:
         reveal_type(m)  # N: Revealed type is "__main__.Medal"
 
 [case testMatchNarrowUsingPatternGuardSpecialCase]
-def f(x: int | str) -> int:  # E: Missing return statement
+def f(x: int | str) -> int:
     match x:
         case x if isinstance(x, str):
             return 0
@@ -1973,3 +1973,46 @@ def f2(x: T) -> None:
         case DataFrame():  # type: ignore[misc]
             pass
 [builtins fixtures/primitives.pyi]
+
+[case testMatchGuardReachability]
+# flags: --warn-unreachable
+def f1(e: int) -> int:
+    match e:
+        case x if True:
+            return x
+        case _:
+            return 0  # E: Statement is unreachable
+    e = 0  # E: Statement is unreachable
+
+
+def f2(e: int) -> int:
+    match e:
+        case x if bool():
+            return x
+        case _:
+            return 0
+    e = 0  # E: Statement is unreachable
+
+def f3(e: int | str | bytes) -> int:
+    match e:
+        case x if isinstance(x, int):
+            return x
+        case [x]:
+            return 0  # E: Statement is unreachable
+        case str(x):
+            return 0
+    reveal_type(e)  # N: Revealed type is "builtins.bytes"
+    return 0
+
+def f4(e: int | str | bytes) -> int:
+    match e:
+        case int(x):
+            pass
+        case [x]:
+            return 0  # E: Statement is unreachable
+        case x if isinstance(x, str):
+            return 0
+    reveal_type(e)  # N: Revealed type is "Union[builtins.int, builtins.bytes]"
+    return 0
+
+[builtins fixtures/primitives.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchNarrowUsingPatternGuardSpecialCase mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchGuardReachability
: '>>>>> End Test Output'
git checkout 14418bc3d2c38b9ea776da6029e9d9dc6650b7ea -- test-data/unit/check-python310.test 2>/dev/null || true
