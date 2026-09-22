#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e6b91bdc5c253cefba940b0864a8257d833f0d8b -- test-data/unit/check-basic.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-basic.test b/test-data/unit/check-basic.test
--- a/test-data/unit/check-basic.test
+++ b/test-data/unit/check-basic.test
@@ -401,9 +401,18 @@ def foo(
 [case testNoneHasBool]
 none = None
 b = none.__bool__()
-reveal_type(b)  # N: Revealed type is "builtins.bool"
+reveal_type(b)  # N: Revealed type is "Literal[False]"
 [builtins fixtures/bool.pyi]
 
+[case testNoneHasBoolShowNoneErrorsFalse]
+none = None
+b = none.__bool__()
+reveal_type(b)  # N: Revealed type is "Literal[False]"
+[builtins fixtures/bool.pyi]
+[file mypy.ini]
+\[mypy]
+show_none_errors = False
+
 [case testAssignmentInvariantNoteForList]
 from typing import List
 x: List[int]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testNoneHasBool mypy/test/testcheck.py::TypeCheckSuite::testNoneHasBoolShowNoneErrorsFalse mypy/test/testcheck.py::TypeCheckSuite::testAssignmentInvariantNoteForList
: '>>>>> End Test Output'
git checkout e6b91bdc5c253cefba940b0864a8257d833f0d8b -- test-data/unit/check-basic.test 2>/dev/null || true
