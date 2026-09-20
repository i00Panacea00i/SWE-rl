#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout a5a9e1554b0f637ccb2fd9c0d3b0eb17836fc54a -- test-data/unit/check-generic-alias.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-generic-alias.test b/test-data/unit/check-generic-alias.test
--- a/test-data/unit/check-generic-alias.test
+++ b/test-data/unit/check-generic-alias.test
@@ -239,3 +239,46 @@ t09: tuple[int, ...] = (1, 2, 3)
 from typing import Tuple
 t10: Tuple[int, ...] = t09
 [builtins fixtures/tuple.pyi]
+
+[case testTypeAliasWithBuiltinTuple]
+# flags: --python-version 3.9
+
+A = tuple[int, ...]
+a: A = ()
+b: A = (1, 2, 3)
+c: A = ('x', 'y')  # E: Incompatible types in assignment (expression has type "Tuple[str, str]", variable has type "Tuple[int, ...]")
+
+B = tuple[int, str]
+x: B = (1, 'x')
+y: B = ('x', 1)  # E: Incompatible types in assignment (expression has type "Tuple[str, int]", variable has type "Tuple[int, str]")
+
+reveal_type(tuple[int, ...]())  # N: Revealed type is "builtins.tuple[builtins.int*]"
+[builtins fixtures/tuple.pyi]
+
+[case testTypeAliasWithBuiltinTupleInStub]
+# flags: --python-version 3.6
+import m
+reveal_type(m.a)  # N: Revealed type is "builtins.tuple[builtins.int]"
+reveal_type(m.b)  # N: Revealed type is "Tuple[builtins.int, builtins.str]"
+
+[file m.pyi]
+A = tuple[int, ...]
+a: A
+B = tuple[int, str]
+b: B
+[builtins fixtures/tuple.pyi]
+
+[case testTypeAliasWithBuiltinListInStub]
+# flags: --python-version 3.6
+import m
+reveal_type(m.a)  # N: Revealed type is "builtins.list[builtins.int]"
+reveal_type(m.b)  # N: Revealed type is "builtins.list[builtins.list[builtins.int]]"
+
+[file m.pyi]
+A = list[int]
+a: A
+B = list[list[int]]
+b: B
+class C(list[int]):
+    pass
+[builtins fixtures/list.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testTypeAliasWithBuiltinTupleInStub mypy/test/testcheck.py::TypeCheckSuite::testTypeAliasWithBuiltinTuple mypy/test/testcheck.py::TypeCheckSuite::testTypeAliasWithBuiltinListInStub
: '>>>>> End Test Output'
git checkout a5a9e1554b0f637ccb2fd9c0d3b0eb17836fc54a -- test-data/unit/check-generic-alias.test 2>/dev/null || true
