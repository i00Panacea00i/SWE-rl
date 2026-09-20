#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 2907a4dea939e20ff39ef7d9ff85ae1a199a0ee8 -- test-data/unit/check-typevar-values.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-typevar-values.test b/test-data/unit/check-typevar-values.test
--- a/test-data/unit/check-typevar-values.test
+++ b/test-data/unit/check-typevar-values.test
@@ -631,3 +631,74 @@ def g(s: S) -> Callable[[S], None]: ...
 def f(x: S) -> None:
     h = g(x)
     h(x)
+
+[case testTypeVarWithTypedDictBoundInIndexExpression]
+from typing import TypeVar
+from typing_extensions import TypedDict
+
+class Data(TypedDict):
+    x: int
+
+
+T = TypeVar("T", bound=Data)
+
+
+def f(data: T) -> None:
+    reveal_type(data["x"]) # N: Revealed type is "builtins.int"
+[builtins fixtures/tuple.pyi]
+
+[case testTypeVarWithUnionTypedDictBoundInIndexExpression]
+from typing import TypeVar, Union, Dict
+from typing_extensions import TypedDict
+
+class Data(TypedDict):
+    x: int
+
+
+T = TypeVar("T", bound=Union[Data, Dict[str, str]])
+
+
+def f(data: T) -> None:
+    reveal_type(data["x"]) # N: Revealed type is "Union[builtins.int, builtins.str*]"
+
+[builtins fixtures/tuple.pyi]
+[builtins fixtures/dict.pyi]
+
+[case testTypeVarWithTypedDictValueInIndexExpression]
+from typing import TypeVar, Union, Dict
+from typing_extensions import TypedDict
+
+class Data(TypedDict):
+    x: int
+
+
+T = TypeVar("T", Data, Dict[str, str])
+
+
+def f(data: T) -> None:
+    _: Union[str, int] = data["x"]
+[builtins fixtures/tuple.pyi]
+[builtins fixtures/dict.pyi]
+
+[case testSelfTypeVarIndexExpr]
+from typing import TypeVar, Union, Type
+from typing_extensions import TypedDict
+
+T = TypeVar("T", bound="Indexable")
+
+class Indexable:
+    def __init__(self, index: str) -> None:
+        self.index = index 
+
+    def __getitem__(self: T, index: str) -> T:
+        return self._new_instance(index)
+
+    @classmethod
+    def _new_instance(cls: Type[T], index: str) -> T:
+        return cls("foo")
+
+    def m(self: T) -> T:
+        return self["foo"]
+
+[builtins fixtures/tuple.pyi]
+[builtins fixtures/classmethod.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testTypeVarWithUnionTypedDictBoundInIndexExpression mypy/test/testcheck.py::TypeCheckSuite::testTypeVarWithTypedDictBoundInIndexExpression mypy/test/testcheck.py::TypeCheckSuite::testTypeVarWithTypedDictValueInIndexExpression mypy/test/testcheck.py::TypeCheckSuite::testSelfTypeVarIndexExpr
: '>>>>> End Test Output'
git checkout 2907a4dea939e20ff39ef7d9ff85ae1a199a0ee8 -- test-data/unit/check-typevar-values.test 2>/dev/null || true
