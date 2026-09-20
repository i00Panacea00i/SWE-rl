#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 05b9d3110ca68d6550e7ecf4553b4adeae997305 -- tests/test_compute_meandice.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_compute_meandice.py b/tests/test_compute_meandice.py
--- a/tests/test_compute_meandice.py
+++ b/tests/test_compute_meandice.py
@@ -172,9 +172,19 @@
     [[1.0000, 1.0000], [1.0000, 1.0000]],
 ]
 
+TEST_CASE_11 = [
+    {"y": torch.zeros((2, 2, 3, 3)), "y_pred": torch.zeros((2, 2, 3, 3)), "ignore_empty": False},
+    [[1.0000, 1.0000], [1.0000, 1.0000]],
+]
+
+TEST_CASE_12 = [
+    {"y": torch.zeros((2, 2, 3, 3)), "y_pred": torch.ones((2, 2, 3, 3)), "ignore_empty": False},
+    [[0.0000, 0.0000], [0.0000, 0.0000]],
+]
+
 
 class TestComputeMeanDice(unittest.TestCase):
-    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_9])
+    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_9, TEST_CASE_11, TEST_CASE_12])
     def test_value(self, input_data, expected_value):
         result = compute_meandice(**input_data)
         np.testing.assert_allclose(result.cpu().numpy(), expected_value, atol=1e-4)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_compute_meandice.py::TestComputeMeanDice::test_value_3 tests/test_compute_meandice.py::TestComputeMeanDice::test_value_4 tests/test_compute_meandice.py::TestComputeMeanDice::test_value_0 tests/test_compute_meandice.py::TestComputeMeanDice::test_value_class_1 tests/test_compute_meandice.py::TestComputeMeanDice::test_value_class_0 tests/test_compute_meandice.py::TestComputeMeanDice::test_nans_class_2 tests/test_compute_meandice.py::TestComputeMeanDice::test_value_class_2 tests/test_compute_meandice.py::TestComputeMeanDice::test_nans_0 tests/test_compute_meandice.py::TestComputeMeanDice::test_value_1 tests/test_compute_meandice.py::TestComputeMeanDice::test_nans_class_0 tests/test_compute_meandice.py::TestComputeMeanDice::test_value_2 tests/test_compute_meandice.py::TestComputeMeanDice::test_nans_class_3 tests/test_compute_meandice.py::TestComputeMeanDice::test_nans_class_4 tests/test_compute_meandice.py::TestComputeMeanDice::test_nans_class_1
: '>>>>> End Test Output'
git checkout 05b9d3110ca68d6550e7ecf4553b4adeae997305 -- tests/test_compute_meandice.py 2>/dev/null || true
