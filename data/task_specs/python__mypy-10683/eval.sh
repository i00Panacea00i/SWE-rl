#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 2ebdbca3b5afbfa1113f01b583522f4afcc4b3e3 -- test-data/unit/check-typeguard.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-typeguard.test b/test-data/unit/check-typeguard.test
--- a/test-data/unit/check-typeguard.test
+++ b/test-data/unit/check-typeguard.test
@@ -82,6 +82,7 @@ def is_str_list(a: List[object]) -> TypeGuard[List[str]]: pass
 def main(a: List[object]):
     if is_str_list(a):
         reveal_type(a)  # N: Revealed type is "builtins.list[builtins.str]"
+    reveal_type(a)  # N: Revealed type is "builtins.list[builtins.object]"
 [builtins fixtures/tuple.pyi]
 
 [case testTypeGuardUnionIn]
@@ -91,6 +92,7 @@ def is_foo(a: Union[int, str]) -> TypeGuard[str]: pass
 def main(a: Union[str, int]) -> None:
     if is_foo(a):
         reveal_type(a)  # N: Revealed type is "builtins.str"
+    reveal_type(a)  # N: Revealed type is "Union[builtins.str, builtins.int]"
 [builtins fixtures/tuple.pyi]
 
 [case testTypeGuardUnionOut]
@@ -315,3 +317,50 @@ def coverage(obj: Any) -> bool:
         return True
     return False
 [builtins fixtures/classmethod.pyi]
+
+[case testAssignToTypeGuardedVariable1]
+from typing_extensions import TypeGuard
+
+class A: pass
+class B(A): pass
+
+def guard(a: A) -> TypeGuard[B]:
+    pass
+
+a = A()
+if not guard(a):
+    a = A()
+[builtins fixtures/tuple.pyi]
+
+[case testAssignToTypeGuardedVariable2]
+from typing_extensions import TypeGuard
+
+class A: pass
+class B: pass
+
+def guard(a: A) -> TypeGuard[B]:
+    pass
+
+a = A()
+if not guard(a):
+    a = A()
+[builtins fixtures/tuple.pyi]
+
+[case testAssignToTypeGuardedVariable3]
+from typing_extensions import TypeGuard
+
+class A: pass
+class B: pass
+
+def guard(a: A) -> TypeGuard[B]:
+    pass
+
+a = A()
+if guard(a):
+    reveal_type(a)  # N: Revealed type is "__main__.B"
+    a = B()  # E: Incompatible types in assignment (expression has type "B", variable has type "A")
+    reveal_type(a)  # N: Revealed type is "__main__.B"
+    a = A()
+    reveal_type(a)  # N: Revealed type is "__main__.A"
+reveal_type(a)  # N: Revealed type is "__main__.A"
+[builtins fixtures/tuple.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testAssignToTypeGuardedVariable1 mypy/test/testcheck.py::TypeCheckSuite::testAssignToTypeGuardedVariable2 mypy/test/testcheck.py::TypeCheckSuite::testAssignToTypeGuardedVariable3 mypy/test/testcheck.py::TypeCheckSuite::testTypeGuardUnionOut mypy/test/testcheck.py::TypeCheckSuite::testTypeGuardUnionIn
: '>>>>> End Test Output'
git checkout 2ebdbca3b5afbfa1113f01b583522f4afcc4b3e3 -- test-data/unit/check-typeguard.test 2>/dev/null || true
