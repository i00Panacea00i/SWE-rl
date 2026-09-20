#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout cdc956bd209285b43cfca712902be2da04d133f9 -- test-data/unit/check-narrowing.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-narrowing.test b/test-data/unit/check-narrowing.test
--- a/test-data/unit/check-narrowing.test
+++ b/test-data/unit/check-narrowing.test
@@ -2089,3 +2089,28 @@ if isinstance(x, (Z, NoneType)):  # E: Subclass of "X" and "Z" cannot exist: "Z"
     reveal_type(x)  # E: Statement is unreachable
 
 [builtins fixtures/isinstance.pyi]
+
+[case testTypeNarrowingReachableNegative]
+# flags: --warn-unreachable
+from typing import Literal
+
+x: Literal[-1]
+
+if x == -1:
+    assert True
+
+[typing fixtures/typing-medium.pyi]
+[builtins fixtures/ops.pyi]
+
+[case testTypeNarrowingReachableNegativeUnion]
+from typing import Literal
+
+x: Literal[-1, 1]
+
+if x == -1:
+    reveal_type(x)  # N: Revealed type is "Literal[-1]"
+else:
+    reveal_type(x)  # N: Revealed type is "Literal[1]"
+
+[typing fixtures/typing-medium.pyi]
+[builtins fixtures/ops.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-narrowing.test::testTypeNarrowingReachableNegativeUnion mypy/test/testcheck.py::TypeCheckSuite::check-narrowing.test::testTypeNarrowingReachableNegative
: '>>>>> End Test Output'
git checkout cdc956bd209285b43cfca712902be2da04d133f9 -- test-data/unit/check-narrowing.test 2>/dev/null || true
