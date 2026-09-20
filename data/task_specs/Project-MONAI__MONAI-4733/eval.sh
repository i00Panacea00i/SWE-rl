#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 0711ffe5067cd614c619b98b6fb389b0ce4330d2 -- tests/test_to_tensor.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_to_tensor.py b/tests/test_to_tensor.py
--- a/tests/test_to_tensor.py
+++ b/tests/test_to_tensor.py
@@ -40,7 +40,7 @@ def test_array_input(self, test_data, expected_shape):
 
     @parameterized.expand(TESTS_SINGLE)
     def test_single_input(self, test_data):
-        result = ToTensor()(test_data)
+        result = ToTensor(track_meta=True)(test_data)
         self.assertTrue(isinstance(result, torch.Tensor))
         assert_allclose(result, test_data, type_test=False)
         self.assertEqual(result.ndim, 0)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_to_tensor.py::TestToTensor::test_single_input_2 tests/test_to_tensor.py::TestToTensor::test_single_input_0 tests/test_to_tensor.py::TestToTensor::test_single_input_1 tests/test_to_tensor.py::TestToTensor::test_single_input_3 tests/test_to_tensor.py::TestToTensor::test_array_input_0 tests/test_to_tensor.py::TestToTensor::test_array_input_1 tests/test_to_tensor.py::TestToTensor::test_array_input_3 tests/test_to_tensor.py::TestToTensor::test_array_input_2
: '>>>>> End Test Output'
git checkout 0711ffe5067cd614c619b98b6fb389b0ce4330d2 -- tests/test_to_tensor.py 2>/dev/null || true
