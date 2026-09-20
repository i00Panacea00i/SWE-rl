#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 105ce15f4f41278fbd11ea699b1847c59dede690 -- tests/test_activationsd.py tests/test_as_discreted.py tests/test_keep_largest_connected_componentd.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_activationsd.py b/tests/test_activationsd.py
--- a/tests/test_activationsd.py
+++ b/tests/test_activationsd.py
@@ -40,10 +40,24 @@
     (1, 1, 2, 2),
 ]
 
+TEST_CASE_3 = [
+    {"keys": "pred", "output_postfix": "act", "sigmoid": False, "softmax": False, "other": lambda x: torch.tanh(x)},
+    {"pred": torch.tensor([[[[0.0, 1.0], [2.0, 3.0]]]])},
+    {"pred_act": torch.tensor([[[[0.0000, 0.7616], [0.9640, 0.9951]]]])},
+    (1, 1, 2, 2),
+]
+
+TEST_CASE_4 = [
+    {"keys": "pred", "output_postfix": None, "sigmoid": False, "softmax": False, "other": lambda x: torch.tanh(x)},
+    {"pred": torch.tensor([[[[0.0, 1.0], [2.0, 3.0]]]])},
+    {"pred": torch.tensor([[[[0.0000, 0.7616], [0.9640, 0.9951]]]])},
+    (1, 1, 2, 2),
+]
+
 
 class TestActivationsd(unittest.TestCase):
-    @parameterized.expand([TEST_CASE_1, TEST_CASE_2])
-    def test_shape(self, input_param, test_input, output, expected_shape):
+    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3])
+    def test_value_shape(self, input_param, test_input, output, expected_shape):
         result = Activationsd(**input_param)(test_input)
         torch.testing.assert_allclose(result["pred_act"], output["pred_act"])
         self.assertTupleEqual(result["pred_act"].shape, expected_shape)
@@ -51,6 +65,12 @@ def test_shape(self, input_param, test_input, output, expected_shape):
             torch.testing.assert_allclose(result["label_act"], output["label_act"])
             self.assertTupleEqual(result["label_act"].shape, expected_shape)
 
+    @parameterized.expand([TEST_CASE_4])
+    def test_none_postfix(self, input_param, test_input, output, expected_shape):
+        result = Activationsd(**input_param)(test_input)
+        torch.testing.assert_allclose(result["pred"], output["pred"])
+        self.assertTupleEqual(result["pred"].shape, expected_shape)
+
 
 if __name__ == "__main__":
     unittest.main()
diff --git a/tests/test_as_discreted.py b/tests/test_as_discreted.py
--- a/tests/test_as_discreted.py
+++ b/tests/test_as_discreted.py
@@ -65,10 +65,25 @@
     (1, 2, 1, 2),
 ]
 
+TEST_CASE_4 = [
+    {
+        "keys": "pred",
+        "output_postfix": None,
+        "argmax": True,
+        "to_onehot": True,
+        "n_classes": 2,
+        "threshold_values": False,
+        "logit_thresh": 0.5,
+    },
+    {"pred": torch.tensor([[[[0.0, 1.0]], [[2.0, 3.0]]]])},
+    {"pred": torch.tensor([[[[0.0, 0.0]], [[1.0, 1.0]]]])},
+    (1, 2, 1, 2),
+]
+
 
 class TestAsDiscreted(unittest.TestCase):
     @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3])
-    def test_shape(self, input_param, test_input, output, expected_shape):
+    def test_value_shape(self, input_param, test_input, output, expected_shape):
         result = AsDiscreted(**input_param)(test_input)
         torch.testing.assert_allclose(result["pred_discrete"], output["pred_discrete"])
         self.assertTupleEqual(result["pred_discrete"].shape, expected_shape)
@@ -76,6 +91,12 @@ def test_shape(self, input_param, test_input, output, expected_shape):
             torch.testing.assert_allclose(result["label_discrete"], output["label_discrete"])
             self.assertTupleEqual(result["label_discrete"].shape, expected_shape)
 
+    @parameterized.expand([TEST_CASE_4])
+    def test_none_postfix(self, input_param, test_input, output, expected_shape):
+        result = AsDiscreted(**input_param)(test_input)
+        torch.testing.assert_allclose(result["pred"], output["pred"])
+        self.assertTupleEqual(result["pred"].shape, expected_shape)
+
 
 if __name__ == "__main__":
     unittest.main()
diff --git a/tests/test_keep_largest_connected_componentd.py b/tests/test_keep_largest_connected_componentd.py
--- a/tests/test_keep_largest_connected_componentd.py
+++ b/tests/test_keep_largest_connected_componentd.py
@@ -119,6 +119,13 @@
     ),
 ]
 
+TEST_CASE_13 = [
+    "none_postfix",
+    {"keys": ["img"], "output_postfix": None, "independent": False, "applied_values": [1]},
+    grid_1,
+    torch.tensor([[[[0, 0, 1, 0, 0], [0, 2, 1, 1, 1], [0, 2, 1, 0, 0], [0, 2, 0, 1, 0], [2, 2, 0, 0, 2]]]]),
+]
+
 VALID_CASES = [
     TEST_CASE_1,
     TEST_CASE_2,
@@ -147,6 +154,13 @@ def test_correct_results(self, _, args, input_dict, expected):
             result = converter(input_dict)
             torch.allclose(result["img_largestcc"], expected)
 
+    @parameterized.expand([TEST_CASE_13])
+    def test_none_postfix(self, _, args, input_dict, expected):
+        converter = KeepLargestConnectedComponentd(**args)
+        input_dict["img"] = input_dict["img"].cpu()
+        result = converter(input_dict)
+        torch.allclose(result["img"], expected)
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_activationsd.py::TestActivationsd::test_none_postfix_0 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_none_postfix_0_none_postfix tests/test_as_discreted.py::TestAsDiscreted::test_none_postfix_0 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_03_dependent_value_1_2 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_00_value_1 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_10_value_0_background_3 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_05_independent_value_1_2 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_08_independent_value_1_2_connect_1 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_1 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_06_dependent_value_1_2 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_02_independent_value_1_2 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_07_value_1_connect_1 tests/test_activationsd.py::TestActivationsd::test_value_shape_1 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_11_all_0_batch_2 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_04_value_1 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_01_value_2 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_0 tests/test_activationsd.py::TestActivationsd::test_value_shape_0 tests/test_keep_largest_connected_componentd.py::TestKeepLargestConnectedComponentd::test_correct_results_09_dependent_value_1_2_connect_1 tests/test_as_discreted.py::TestAsDiscreted::test_value_shape_2 tests/test_activationsd.py::TestActivationsd::test_value_shape_2
: '>>>>> End Test Output'
git checkout 105ce15f4f41278fbd11ea699b1847c59dede690 -- tests/test_activationsd.py tests/test_as_discreted.py tests/test_keep_largest_connected_componentd.py 2>/dev/null || true
