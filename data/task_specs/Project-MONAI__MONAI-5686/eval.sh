#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 25130db17751bb709e841b9727f34936a84f9093 -- tests/test_ssim_loss.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_ssim_loss.py b/tests/test_ssim_loss.py
--- a/tests/test_ssim_loss.py
+++ b/tests/test_ssim_loss.py
@@ -34,6 +34,14 @@
     TESTS3D.append((x.to(device), y1.to(device), data_range.to(device), torch.tensor(1.0).unsqueeze(0).to(device)))
     TESTS3D.append((x.to(device), y2.to(device), data_range.to(device), torch.tensor(0.0).unsqueeze(0).to(device)))
 
+x = torch.ones([1, 1, 10, 10]) / 2
+y = torch.ones([1, 1, 10, 10]) / 2
+y.requires_grad_(True)
+data_range = x.max().unsqueeze(0)
+TESTS2D_GRAD = []
+for device in [None, "cpu", "cuda"] if torch.cuda.is_available() else [None, "cpu"]:
+    TESTS2D_GRAD.append([x.to(device), y.to(device), data_range.to(device)])
+
 
 class TestSSIMLoss(unittest.TestCase):
     @parameterized.expand(TESTS2D)
@@ -42,6 +50,11 @@ def test2d(self, x, y, drange, res):
         self.assertTrue(isinstance(result, torch.Tensor))
         self.assertTrue(torch.abs(res - result).item() < 0.001)
 
+    @parameterized.expand(TESTS2D_GRAD)
+    def test_grad(self, x, y, drange):
+        result = 1 - SSIMLoss(spatial_dims=2)(x, y, drange)
+        self.assertTrue(result.requires_grad)
+
     @parameterized.expand(TESTS3D)
     def test3d(self, x, y, drange, res):
         result = 1 - SSIMLoss(spatial_dims=3)(x, y, drange)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_ssim_loss.py::TestSSIMLoss::test_grad_1 tests/test_ssim_loss.py::TestSSIMLoss::test_grad_0 tests/test_ssim_loss.py::TestSSIMLoss::test3d_2 tests/test_ssim_loss.py::TestSSIMLoss::test3d_1 tests/test_ssim_loss.py::TestSSIMLoss::test3d_3 tests/test_ssim_loss.py::TestSSIMLoss::test2d_2 tests/test_ssim_loss.py::TestSSIMLoss::test2d_1 tests/test_ssim_loss.py::TestSSIMLoss::test3d_0 tests/test_ssim_loss.py::TestSSIMLoss::test2d_3 tests/test_ssim_loss.py::TestSSIMLoss::test2d_0
: '>>>>> End Test Output'
git checkout 25130db17751bb709e841b9727f34936a84f9093 -- tests/test_ssim_loss.py 2>/dev/null || true
