#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout b2cc1668c0fe5b961721e5387ac6bc992e72d4d7 -- tests/test_compute_roc_auc.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_compute_roc_auc.py b/tests/test_compute_roc_auc.py
--- a/tests/test_compute_roc_auc.py
+++ b/tests/test_compute_roc_auc.py
@@ -68,9 +68,20 @@
     0.62,
 ]
 
+TEST_CASE_8 = [
+    torch.tensor([[0.1, 0.9], [0.3, 1.4], [0.2, 0.1], [0.1, 0.5]]),
+    torch.tensor([[0], [0], [0], [0]]),
+    True,
+    2,
+    "macro",
+    float("nan"),
+]
+
 
 class TestComputeROCAUC(unittest.TestCase):
-    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4, TEST_CASE_5, TEST_CASE_6, TEST_CASE_7])
+    @parameterized.expand(
+        [TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4, TEST_CASE_5, TEST_CASE_6, TEST_CASE_7, TEST_CASE_8]
+    )
     def test_value(self, y_pred, y, softmax, to_onehot, average, expected_value):
         y_pred_trans = Compose([ToTensor(), Activations(softmax=softmax)])
         y_trans = Compose([ToTensor(), AsDiscrete(to_onehot=to_onehot)])
@@ -79,7 +90,9 @@ def test_value(self, y_pred, y, softmax, to_onehot, average, expected_value):
         result = compute_roc_auc(y_pred=y_pred, y=y, average=average)
         np.testing.assert_allclose(expected_value, result, rtol=1e-5)
 
-    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4, TEST_CASE_5, TEST_CASE_6, TEST_CASE_7])
+    @parameterized.expand(
+        [TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4, TEST_CASE_5, TEST_CASE_6, TEST_CASE_7, TEST_CASE_8]
+    )
     def test_class_value(self, y_pred, y, softmax, to_onehot, average, expected_value):
         y_pred_trans = Compose([ToTensor(), Activations(softmax=softmax)])
         y_trans = Compose([ToTensor(), AsDiscrete(to_onehot=to_onehot)])

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_compute_roc_auc.py::TestComputeROCAUC::test_value_7 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_class_value_7 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_class_value_5 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_value_4 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_class_value_1 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_value_3 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_value_5 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_value_0 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_class_value_2 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_value_6 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_class_value_4 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_value_1 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_class_value_6 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_class_value_3 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_class_value_0 tests/test_compute_roc_auc.py::TestComputeROCAUC::test_value_2
: '>>>>> End Test Output'
git checkout b2cc1668c0fe5b961721e5387ac6bc992e72d4d7 -- tests/test_compute_roc_auc.py 2>/dev/null || true
