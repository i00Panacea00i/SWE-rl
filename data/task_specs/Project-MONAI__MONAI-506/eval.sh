#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 549da3f41ba21d7463e8b83cd389ea3856cf0221 -- tests/test_squeezedim.py tests/test_squeezedimd.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_squeezedim.py b/tests/test_squeezedim.py
--- a/tests/test_squeezedim.py
+++ b/tests/test_squeezedim.py
@@ -10,8 +10,11 @@
 # limitations under the License.
 
 import unittest
+
 import numpy as np
+import torch
 from parameterized import parameterized
+
 from monai.transforms import SqueezeDim
 
 TEST_CASE_1 = [{"dim": None}, np.random.rand(1, 2, 1, 3), (2, 3)]
@@ -20,7 +23,9 @@
 
 TEST_CASE_3 = [{"dim": -1}, np.random.rand(1, 1, 16, 8, 1), (1, 1, 16, 8)]
 
-TEST_CASE_4 = [{}, np.random.rand(1, 2, 1, 3), (2, 3)]
+TEST_CASE_4 = [{}, np.random.rand(1, 2, 1, 3), (2, 1, 3)]
+
+TEST_CASE_4_PT = [{}, torch.rand(1, 2, 1, 3), (2, 1, 3)]
 
 TEST_CASE_5 = [
     {"dim": -2},
@@ -34,15 +39,15 @@
 
 
 class TestSqueezeDim(unittest.TestCase):
-    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4])
+    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4, TEST_CASE_4_PT])
     def test_shape(self, input_param, test_data, expected_shape):
         result = SqueezeDim(**input_param)(test_data)
         self.assertTupleEqual(result.shape, expected_shape)
 
     @parameterized.expand([TEST_CASE_5, TEST_CASE_6])
     def test_invalid_inputs(self, input_param, test_data):
-        with self.assertRaises(AssertionError):
-            result = SqueezeDim(**input_param)(test_data)
+        with self.assertRaises(ValueError):
+            SqueezeDim(**input_param)(test_data)
 
 
 if __name__ == "__main__":
diff --git a/tests/test_squeezedimd.py b/tests/test_squeezedimd.py
--- a/tests/test_squeezedimd.py
+++ b/tests/test_squeezedimd.py
@@ -10,10 +10,12 @@
 # limitations under the License.
 
 import unittest
+
 import numpy as np
+import torch
 from parameterized import parameterized
-from monai.transforms import SqueezeDimd
 
+from monai.transforms import SqueezeDimd
 
 TEST_CASE_1 = [
     {"keys": ["img", "seg"], "dim": None},
@@ -36,7 +38,13 @@
 TEST_CASE_4 = [
     {"keys": ["img", "seg"]},
     {"img": np.random.rand(1, 2, 1, 3), "seg": np.random.randint(0, 2, size=[1, 2, 1, 3])},
-    (2, 3),
+    (2, 1, 3),
+]
+
+TEST_CASE_4_PT = [
+    {"keys": ["img", "seg"], "dim": 0},
+    {"img": torch.rand(1, 2, 1, 3), "seg": torch.randint(0, 2, size=[1, 2, 1, 3])},
+    (2, 1, 3),
 ]
 
 TEST_CASE_5 = [
@@ -51,7 +59,7 @@
 
 
 class TestSqueezeDim(unittest.TestCase):
-    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4])
+    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4, TEST_CASE_4_PT])
     def test_shape(self, input_param, test_data, expected_shape):
         result = SqueezeDimd(**input_param)(test_data)
         self.assertTupleEqual(result["img"].shape, expected_shape)
@@ -59,8 +67,8 @@ def test_shape(self, input_param, test_data, expected_shape):
 
     @parameterized.expand([TEST_CASE_5, TEST_CASE_6])
     def test_invalid_inputs(self, input_param, test_data):
-        with self.assertRaises(AssertionError):
-            result = SqueezeDimd(**input_param)(test_data)
+        with self.assertRaises(ValueError):
+            SqueezeDimd(**input_param)(test_data)
 
 
 if __name__ == "__main__":

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_squeezedim.py::TestSqueezeDim::test_shape_4 tests/test_squeezedim.py::TestSqueezeDim::test_invalid_inputs_1 tests/test_squeezedim.py::TestSqueezeDim::test_invalid_inputs_0 tests/test_squeezedim.py::TestSqueezeDim::test_shape_3 tests/test_squeezedimd.py::TestSqueezeDim::test_invalid_inputs_1 tests/test_squeezedimd.py::TestSqueezeDim::test_invalid_inputs_0 tests/test_squeezedimd.py::TestSqueezeDim::test_shape_3 tests/test_squeezedimd.py::TestSqueezeDim::test_shape_1 tests/test_squeezedimd.py::TestSqueezeDim::test_shape_4 tests/test_squeezedim.py::TestSqueezeDim::test_shape_1 tests/test_squeezedimd.py::TestSqueezeDim::test_shape_2 tests/test_squeezedimd.py::TestSqueezeDim::test_shape_0 tests/test_squeezedim.py::TestSqueezeDim::test_shape_0 tests/test_squeezedim.py::TestSqueezeDim::test_shape_2
: '>>>>> End Test Output'
git checkout 549da3f41ba21d7463e8b83cd389ea3856cf0221 -- tests/test_squeezedim.py tests/test_squeezedimd.py 2>/dev/null || true
