#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout eeafe6b6945eb68eaab7552010c59102b4457be6 -- test-data/unit/check-typeguard.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-typeguard.test b/test-data/unit/check-typeguard.test
--- a/test-data/unit/check-typeguard.test
+++ b/test-data/unit/check-typeguard.test
@@ -458,3 +458,92 @@ def foobar_typeguard(x: object):
         return
     reveal_type(x)  # N: Revealed type is "__main__.<subclass of "Foo" and "Bar">"
 [builtins fixtures/tuple.pyi]
+
+[case testTypeGuardAsFunctionArgAsBoolSubtype]
+from typing import Callable
+from typing_extensions import TypeGuard
+
+def accepts_bool(f: Callable[[object], bool]): pass
+
+def with_bool_typeguard(o: object) -> TypeGuard[bool]: pass
+def with_str_typeguard(o: object) -> TypeGuard[str]: pass
+def with_bool(o: object) -> bool: pass
+
+accepts_bool(with_bool_typeguard)
+accepts_bool(with_str_typeguard)
+accepts_bool(with_bool)
+[builtins fixtures/tuple.pyi]
+
+[case testTypeGuardAsFunctionArg]
+from typing import Callable
+from typing_extensions import TypeGuard
+
+def accepts_typeguard(f: Callable[[object], TypeGuard[bool]]): pass
+def different_typeguard(f: Callable[[object], TypeGuard[str]]): pass
+
+def with_typeguard(o: object) -> TypeGuard[bool]: pass
+def with_bool(o: object) -> bool: pass
+
+accepts_typeguard(with_typeguard)
+accepts_typeguard(with_bool)  # E: Argument 1 to "accepts_typeguard" has incompatible type "Callable[[object], bool]"; expected "Callable[[object], TypeGuard[bool]]"
+
+different_typeguard(with_typeguard)  # E: Argument 1 to "different_typeguard" has incompatible type "Callable[[object], TypeGuard[bool]]"; expected "Callable[[object], TypeGuard[str]]"
+different_typeguard(with_bool)  # E: Argument 1 to "different_typeguard" has incompatible type "Callable[[object], bool]"; expected "Callable[[object], TypeGuard[str]]"
+[builtins fixtures/tuple.pyi]
+
+[case testTypeGuardAsGenericFunctionArg]
+from typing import Callable, TypeVar
+from typing_extensions import TypeGuard
+
+T = TypeVar('T')
+
+def accepts_typeguard(f: Callable[[object], TypeGuard[T]]): pass
+
+def with_bool_typeguard(o: object) -> TypeGuard[bool]: pass
+def with_str_typeguard(o: object) -> TypeGuard[str]: pass
+def with_bool(o: object) -> bool: pass
+
+accepts_typeguard(with_bool_typeguard)
+accepts_typeguard(with_str_typeguard)
+accepts_typeguard(with_bool)  # E: Argument 1 to "accepts_typeguard" has incompatible type "Callable[[object], bool]"; expected "Callable[[object], TypeGuard[bool]]"
+[builtins fixtures/tuple.pyi]
+
+[case testTypeGuardAsOverloadedFunctionArg]
+# https://github.com/python/mypy/issues/11307
+from typing import Callable, TypeVar, Generic, Any, overload
+from typing_extensions import TypeGuard
+
+_T = TypeVar('_T')
+
+class filter(Generic[_T]):
+    @overload
+    def __init__(self, function: Callable[[object], TypeGuard[_T]]) -> None: pass
+    @overload
+    def __init__(self, function: Callable[[_T], Any]) -> None: pass
+    def __init__(self, function): pass
+
+def is_int_typeguard(a: object) -> TypeGuard[int]: pass
+def returns_bool(a: object) -> bool: pass
+
+reveal_type(filter(is_int_typeguard))  # N: Revealed type is "__main__.filter[builtins.int*]"
+reveal_type(filter(returns_bool))  # N: Revealed type is "__main__.filter[builtins.object*]"
+[builtins fixtures/tuple.pyi]
+
+[case testTypeGuardSubtypingVariance]
+from typing import Callable
+from typing_extensions import TypeGuard
+
+class A: pass
+class B(A): pass
+class C(B): pass
+
+def accepts_typeguard(f: Callable[[object], TypeGuard[B]]): pass
+
+def with_typeguard_a(o: object) -> TypeGuard[A]: pass
+def with_typeguard_b(o: object) -> TypeGuard[B]: pass
+def with_typeguard_c(o: object) -> TypeGuard[C]: pass
+
+accepts_typeguard(with_typeguard_a)  # E: Argument 1 to "accepts_typeguard" has incompatible type "Callable[[object], TypeGuard[A]]"; expected "Callable[[object], TypeGuard[B]]"
+accepts_typeguard(with_typeguard_b)
+accepts_typeguard(with_typeguard_c)
+[builtins fixtures/tuple.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testTypeGuardAsFunctionArg mypy/test/testcheck.py::TypeCheckSuite::testTypeGuardSubtypingVariance mypy/test/testcheck.py::TypeCheckSuite::testTypeGuardAsOverloadedFunctionArg mypy/test/testcheck.py::TypeCheckSuite::testTypeGuardAsGenericFunctionArg mypy/test/testcheck.py::TypeCheckSuite::testTypeGuardAsFunctionArgAsBoolSubtype
: '>>>>> End Test Output'
git checkout eeafe6b6945eb68eaab7552010c59102b4457be6 -- test-data/unit/check-typeguard.test 2>/dev/null || true
