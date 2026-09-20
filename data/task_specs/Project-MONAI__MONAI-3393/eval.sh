#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 839f7ef0536129df806bc2f9317bc9e65e3eee70 -- tests/test_as_discrete.py tests/test_as_discreted.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_as_discrete.py b/tests/test_as_discrete.py
--- a/tests/test_as_discrete.py
+++ b/tests/test_as_discrete.py
@@ -45,6 +45,16 @@
         ]
     )
 
+    # test threshold = 0.0
+    TEST_CASES.append(
+        [
+            {"argmax": False, "to_onehot": None, "threshold": 0.0},
+            p([[[0.0, -1.0], [-2.0, 3.0]]]),
+            p([[[1.0, 0.0], [0.0, 1.0]]]),
+            (1, 2, 2),
+        ]
+    )
+
     TEST_CASES.append([{"argmax": False, "to_onehot": 3}, p(1), p([0.0, 1.0, 0.0]), (3,)])
 
     TEST_CASES.append(
diff --git a/tests/test_as_discreted.py b/tests/test_as_discreted.py
--- a/tests/test_as_discreted.py
+++ b/tests/test_as_discreted.py
@@ -70,6 +70,16 @@
         ]
     )
 
+    # test threshold = 0.0
+    TEST_CASES.append(
+        [
+            {"keys": ["pred", "label"], "argmax": False, "to_onehot": None, "threshold": [0.0, None]},
+            {"pred": p([[[0.0, -1.0], [-2.0, 3.0]]]), "label": p([[[0, 1], [1, 1]]])},
+            {"pred": p([[[1.0, 0.0], [0.0, 1.0]]]), "label": p([[[0.0, 1.0], [1.0, 1.0]]])},
+            (1, 2, 2),
+        ]
+    )
+
 
 class TestAsDiscreted(unittest.TestCase):
     @parameterized.expand(TEST_CASES)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_11 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_05 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_09 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_04 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_07 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_06 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_04 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_03 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_00 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_02 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_08 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_09 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_00 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_01 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_07 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_01 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_08 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_11 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_10 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_10 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_06 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_05 tests/test_as_discrete.py::TestAsDiscrete::test_value_shape_02 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_03
: '>>>>> End Test Output'
git checkout 839f7ef0536129df806bc2f9317bc9e65e3eee70 -- tests/test_as_discrete.py tests/test_as_discreted.py 2>/dev/null || true
