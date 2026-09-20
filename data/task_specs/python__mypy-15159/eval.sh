#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 6b1fc865902bf2b845d3c58b6b9973b5a412241f -- test-data/unit/check-recursive-types.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-recursive-types.test b/test-data/unit/check-recursive-types.test
--- a/test-data/unit/check-recursive-types.test
+++ b/test-data/unit/check-recursive-types.test
@@ -897,3 +897,29 @@ Example = NamedTuple("Example", [("rec", List["Example"])])
 e: Example
 reveal_type(e)  # N: Revealed type is "Tuple[builtins.list[...], fallback=__main__.Example]"
 [builtins fixtures/tuple.pyi]
+
+[case testRecursiveBoundFunctionScopeNoCrash]
+from typing import TypeVar, Union, Dict
+
+def dummy() -> None:
+    A = Union[str, Dict[str, "A"]]  # E: Cannot resolve name "A" (possible cyclic definition) \
+                                    # N: Recursive types are not allowed at function scope
+    T = TypeVar("T", bound=A)
+
+    def bar(x: T) -> T:
+        pass
+    reveal_type(bar)  # N: Revealed type is "def [T <: Union[builtins.str, builtins.dict[builtins.str, Any]]] (x: T`-1) -> T`-1"
+[builtins fixtures/dict.pyi]
+
+[case testForwardBoundFunctionScopeWorks]
+from typing import TypeVar, Dict
+
+def dummy() -> None:
+    A = Dict[str, "B"]
+    B = Dict[str, str]
+    T = TypeVar("T", bound=A)
+
+    def bar(x: T) -> T:
+        pass
+    reveal_type(bar)  # N: Revealed type is "def [T <: builtins.dict[builtins.str, builtins.dict[builtins.str, builtins.str]]] (x: T`-1) -> T`-1"
+[builtins fixtures/dict.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-recursive-types.test::testForwardBoundFunctionScopeWorks mypy/test/testcheck.py::TypeCheckSuite::check-recursive-types.test::testRecursiveBoundFunctionScopeNoCrash
: '>>>>> End Test Output'
git checkout 6b1fc865902bf2b845d3c58b6b9973b5a412241f -- test-data/unit/check-recursive-types.test 2>/dev/null || true
