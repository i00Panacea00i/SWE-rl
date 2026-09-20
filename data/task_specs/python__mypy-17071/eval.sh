#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 4310586460e0af07fa8994a0b4f03cb323e352f0 -- test-data/unit/check-typeguard.test test-data/unit/check-typeis.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-typeguard.test b/test-data/unit/check-typeguard.test
--- a/test-data/unit/check-typeguard.test
+++ b/test-data/unit/check-typeguard.test
@@ -54,6 +54,18 @@ def main(a: object, b: object) -> None:
         reveal_type(b)  # N: Revealed type is "builtins.object"
 [builtins fixtures/tuple.pyi]
 
+[case testTypeGuardTypeVarReturn]
+from typing import Callable, Optional, TypeVar
+from typing_extensions import TypeGuard
+T = TypeVar('T')
+def is_str(x: object) -> TypeGuard[str]: pass
+def main(x: object, type_check_func: Callable[[object], TypeGuard[T]]) -> T:
+    if not type_check_func(x):
+        raise Exception()
+    return x
+reveal_type(main("a", is_str))  # N: Revealed type is "builtins.str"
+[builtins fixtures/exception.pyi]
+
 [case testTypeGuardIsBool]
 from typing_extensions import TypeGuard
 def f(a: TypeGuard[int]) -> None: pass
diff --git a/test-data/unit/check-typeis.test b/test-data/unit/check-typeis.test
--- a/test-data/unit/check-typeis.test
+++ b/test-data/unit/check-typeis.test
@@ -92,6 +92,18 @@ def main(a: Tuple[object, ...]):
         reveal_type(a)  # N: Revealed type is "builtins.tuple[builtins.int, ...]"
 [builtins fixtures/tuple.pyi]
 
+[case testTypeIsTypeVarReturn]
+from typing import Callable, Optional, TypeVar
+from typing_extensions import TypeIs
+T = TypeVar('T')
+def is_str(x: object) -> TypeIs[str]: pass
+def main(x: object, type_check_func: Callable[[object], TypeIs[T]]) -> T:
+    if not type_check_func(x):
+        raise Exception()
+    return x
+reveal_type(main("a", is_str))  # N: Revealed type is "builtins.str"
+[builtins fixtures/exception.pyi]
+
 [case testTypeIsUnionIn]
 from typing import Union
 from typing_extensions import TypeIs

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-typeguard.test::testTypeGuardTypeVarReturn mypy/test/testcheck.py::TypeCheckSuite::check-typeis.test::testTypeIsTypeVarReturn mypy/test/testcheck.py::TypeCheckSuite::check-typeis.test::testTypeIsUnionIn mypy/test/testcheck.py::TypeCheckSuite::check-typeguard.test::testTypeGuardIsBool
: '>>>>> End Test Output'
git checkout 4310586460e0af07fa8994a0b4f03cb323e352f0 -- test-data/unit/check-typeguard.test test-data/unit/check-typeis.test 2>/dev/null || true
