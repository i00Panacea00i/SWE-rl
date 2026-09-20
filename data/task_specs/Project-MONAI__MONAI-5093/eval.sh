#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 0af5e18fd5ce2e8733d22096da1cead3b7e6b65c -- tests/test_contrastive_loss.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_contrastive_loss.py b/tests/test_contrastive_loss.py
--- a/tests/test_contrastive_loss.py
+++ b/tests/test_contrastive_loss.py
@@ -19,12 +19,12 @@
 
 TEST_CASES = [
     [  # shape: (1, 4), (1, 4)
-        {"temperature": 0.5, "batch_size": 1},
+        {"temperature": 0.5},
         {"input": torch.tensor([[1.0, 1.0, 0.0, 0.0]]), "target": torch.tensor([[1.0, 1.0, 0.0, 0.0]])},
         0.0,
     ],
     [  # shape: (2, 4), (2, 4)
-        {"temperature": 0.5, "batch_size": 2},
+        {"temperature": 0.5},
         {
             "input": torch.tensor([[1.0, 1.0, 0.0, 0.0], [1.0, 1.0, 0.0, 0.0]]),
             "target": torch.tensor([[1.0, 1.0, 0.0, 0.0], [1.0, 1.0, 0.0, 0.0]]),
@@ -32,7 +32,7 @@
         1.0986,
     ],
     [  # shape: (1, 4), (1, 4)
-        {"temperature": 0.5, "batch_size": 2},
+        {"temperature": 0.5},
         {
             "input": torch.tensor([[1.0, 2.0, 3.0, 4.0], [1.0, 1.0, 0.0, 0.0]]),
             "target": torch.tensor([[0.0, 0.0, 0.0, 0.0], [1.0, 1.0, 0.0, 0.0]]),
@@ -40,12 +40,12 @@
         0.8719,
     ],
     [  # shape: (1, 4), (1, 4)
-        {"temperature": 0.5, "batch_size": 1},
+        {"temperature": 0.5},
         {"input": torch.tensor([[0.0, 0.0, 1.0, 1.0]]), "target": torch.tensor([[1.0, 1.0, 0.0, 0.0]])},
         0.0,
     ],
     [  # shape: (1, 4), (1, 4)
-        {"temperature": 0.05, "batch_size": 1},
+        {"temperature": 0.05},
         {"input": torch.tensor([[0.0, 0.0, 1.0, 1.0]]), "target": torch.tensor([[1.0, 1.0, 0.0, 0.0]])},
         0.0,
     ],
@@ -60,12 +60,12 @@ def test_result(self, input_param, input_data, expected_val):
         np.testing.assert_allclose(result.detach().cpu().numpy(), expected_val, atol=1e-4, rtol=1e-4)
 
     def test_ill_shape(self):
-        loss = ContrastiveLoss(temperature=0.5, batch_size=1)
+        loss = ContrastiveLoss(temperature=0.5)
         with self.assertRaisesRegex(ValueError, ""):
             loss(torch.ones((1, 2, 3)), torch.ones((1, 1, 2, 3)))
 
     def test_with_cuda(self):
-        loss = ContrastiveLoss(temperature=0.5, batch_size=1)
+        loss = ContrastiveLoss(temperature=0.5)
         i = torch.ones((1, 10))
         j = torch.ones((1, 10))
         if torch.cuda.is_available():
@@ -74,6 +74,10 @@ def test_with_cuda(self):
         output = loss(i, j)
         np.testing.assert_allclose(output.detach().cpu().numpy(), 0.0, atol=1e-4, rtol=1e-4)
 
+    def check_warning_rasied(self):
+        with self.assertWarns(Warning):
+            ContrastiveLoss(temperature=0.5, batch_size=1)
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_contrastive_loss.py::TestContrastiveLoss::test_result_1 tests/test_contrastive_loss.py::TestContrastiveLoss::test_result_2 tests/test_contrastive_loss.py::TestContrastiveLoss::test_result_0 tests/test_contrastive_loss.py::TestContrastiveLoss::test_with_cuda tests/test_contrastive_loss.py::TestContrastiveLoss::test_result_4 tests/test_contrastive_loss.py::TestContrastiveLoss::test_result_3 tests/test_contrastive_loss.py::TestContrastiveLoss::test_ill_shape
: '>>>>> End Test Output'
git checkout 0af5e18fd5ce2e8733d22096da1cead3b7e6b65c -- tests/test_contrastive_loss.py 2>/dev/null || true
