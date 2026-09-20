#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 44925f4b121392135440f53d7c8a3fb30593d6cc -- test-data/unit/check-tuples.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-tuples.test b/test-data/unit/check-tuples.test
--- a/test-data/unit/check-tuples.test
+++ b/test-data/unit/check-tuples.test
@@ -1470,3 +1470,29 @@ x9, y9, x10, y10, z5 = *points2, 1, *points2 # E: Contiguous iterable with same
 [case testAssignEmptyBogus]
 () = 1  # E: "Literal[1]?" object is not iterable
 [builtins fixtures/tuple.pyi]
+
+[case testSingleUndefinedTypeAndTuple]
+from typing import Tuple
+
+class Foo:
+    ...
+
+class Bar(aaaaaaaaaa):  # E: Name "aaaaaaaaaa" is not defined
+    ...
+
+class FooBarTuple(Tuple[Foo, Bar]):
+    ...
+[builtins fixtures/tuple.pyi]
+
+[case testMultipleUndefinedTypeAndTuple]
+from typing import Tuple
+
+class Foo(aaaaaaaaaa):  # E: Name "aaaaaaaaaa" is not defined
+    ...
+
+class Bar(aaaaaaaaaa):  # E: Name "aaaaaaaaaa" is not defined
+    ...
+
+class FooBarTuple(Tuple[Foo, Bar]):
+    ...
+[builtins fixtures/tuple.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testMultipleUndefinedTypeAndTuple mypy/test/testcheck.py::TypeCheckSuite::testSingleUndefinedTypeAndTuple mypy/test/testcheck.py::TypeCheckSuite::testAssignEmptyBogus
: '>>>>> End Test Output'
git checkout 44925f4b121392135440f53d7c8a3fb30593d6cc -- test-data/unit/check-tuples.test 2>/dev/null || true
