#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 5db3e1a024a98af4184d6864c71d6abbf00dc3b3 -- test-data/unit/check-tuples.test test-data/unit/semanal-errors.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-tuples.test b/test-data/unit/check-tuples.test
--- a/test-data/unit/check-tuples.test
+++ b/test-data/unit/check-tuples.test
@@ -1458,3 +1458,15 @@ x7, x8, y7, y8 = *points2, *points3 # E: Contiguous iterable with same type expe
 
 x9, y9, x10, y10, z5 = *points2, 1, *points2 # E: Contiguous iterable with same type expected
 [builtins fixtures/tuple.pyi]
+
+[case testAssignEmptyPy36]
+# flags: --python-version 3.6
+() = []
+
+[case testAssignEmptyPy27]
+# flags: --python-version 2.7
+() = []  # E: can't assign to ()
+
+[case testAssignEmptyBogus]
+() = 1  # E: 'Literal[1]?' object is not iterable
+[builtins fixtures/tuple.pyi]
diff --git a/test-data/unit/semanal-errors.test b/test-data/unit/semanal-errors.test
--- a/test-data/unit/semanal-errors.test
+++ b/test-data/unit/semanal-errors.test
@@ -377,11 +377,6 @@ main:1: error: can't assign to literal
 [out]
 main:1: error: can't assign to literal
 
-[case testInvalidLvalues5]
-() = 1
-[out]
-main:1: error: can't assign to ()
-
 [case testInvalidLvalues6]
 x = y = z = 1  # ok
 x, (y, 1) = 1

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testAssignEmptyBogus mypy/test/testcheck.py::TypeCheckSuite::testAssignEmptyPy36 mypy/test/testsemanal.py::SemAnalErrorSuite::testInvalidLvalues6 mypy/test/testcheck.py::TypeCheckSuite::testAssignEmptyPy27
: '>>>>> End Test Output'
git checkout 5db3e1a024a98af4184d6864c71d6abbf00dc3b3 -- test-data/unit/check-tuples.test test-data/unit/semanal-errors.test 2>/dev/null || true
