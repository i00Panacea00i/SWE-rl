#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 80c09d56c080cad93847eeee50ddddf5e3abab06 -- test-data/unit/check-python310.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-python310.test b/test-data/unit/check-python310.test
--- a/test-data/unit/check-python310.test
+++ b/test-data/unit/check-python310.test
@@ -1600,3 +1600,31 @@ def foo(x: NoneType): # E: NoneType should not be used as a type, please use Non
     reveal_type(x) # N: Revealed type is "None"
 
 [builtins fixtures/tuple.pyi]
+
+[case testMatchTupleInstanceUnionNoCrash]
+from typing import Union
+
+def func(e: Union[str, tuple[str]]) -> None:
+    match e:
+        case (a,) if isinstance(a, str):
+            reveal_type(a)  # N: Revealed type is "builtins.str"
+[builtins fixtures/tuple.pyi]
+
+[case testMatchTupleOptionalNoCrash]
+# flags: --strict-optional
+foo: tuple[int] | None
+match foo:
+    case x,:
+        reveal_type(x)  # N: Revealed type is "builtins.int"
+[builtins fixtures/tuple.pyi]
+
+[case testMatchUnionTwoTuplesNoCrash]
+var: tuple[int, int] | tuple[str, str]
+
+# TODO: we can infer better here.
+match var:
+    case (42, a):
+        reveal_type(a)  # N: Revealed type is "Union[builtins.int, builtins.str]"
+    case ("yes", b):
+        reveal_type(b)  # N: Revealed type is "Union[builtins.int, builtins.str]"
+[builtins fixtures/tuple.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchUnionTwoTuplesNoCrash mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchTupleInstanceUnionNoCrash mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchTupleOptionalNoCrash
: '>>>>> End Test Output'
git checkout 80c09d56c080cad93847eeee50ddddf5e3abab06 -- test-data/unit/check-python310.test 2>/dev/null || true
