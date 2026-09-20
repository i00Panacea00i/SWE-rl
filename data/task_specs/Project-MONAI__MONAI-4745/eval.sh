#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 9c12cd8aab54e31f7c87956ca6fc20573d2148ec -- tests/test_concat_itemsd.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_concat_itemsd.py b/tests/test_concat_itemsd.py
--- a/tests/test_concat_itemsd.py
+++ b/tests/test_concat_itemsd.py
@@ -14,6 +14,7 @@
 import numpy as np
 import torch
 
+from monai.data import MetaTensor
 from monai.transforms import ConcatItemsd
 
 
@@ -30,6 +31,20 @@ def test_tensor_values(self):
         torch.testing.assert_allclose(result["img1"], torch.tensor([[0, 1], [1, 2]], device=device))
         torch.testing.assert_allclose(result["cat_img"], torch.tensor([[1, 2], [2, 3], [1, 2], [2, 3]], device=device))
 
+    def test_metatensor_values(self):
+        device = torch.device("cuda:0") if torch.cuda.is_available() else torch.device("cpu:0")
+        input_data = {
+            "img1": MetaTensor([[0, 1], [1, 2]], device=device),
+            "img2": MetaTensor([[0, 1], [1, 2]], device=device),
+        }
+        result = ConcatItemsd(keys=["img1", "img2"], name="cat_img")(input_data)
+        self.assertTrue("cat_img" in result)
+        self.assertTrue(isinstance(result["cat_img"], MetaTensor))
+        self.assertEqual(result["img1"].meta, result["cat_img"].meta)
+        result["cat_img"] += 1
+        torch.testing.assert_allclose(result["img1"], torch.tensor([[0, 1], [1, 2]], device=device))
+        torch.testing.assert_allclose(result["cat_img"], torch.tensor([[1, 2], [2, 3], [1, 2], [2, 3]], device=device))
+
     def test_numpy_values(self):
         input_data = {"img1": np.array([[0, 1], [1, 2]]), "img2": np.array([[0, 1], [1, 2]])}
         result = ConcatItemsd(keys=["img1", "img2"], name="cat_img")(input_data)
@@ -52,6 +67,13 @@ def test_single_tensor(self):
         torch.testing.assert_allclose(result["img"], torch.tensor([[0, 1], [1, 2]]))
         torch.testing.assert_allclose(result["cat_img"], torch.tensor([[1, 2], [2, 3]]))
 
+    def test_single_metatensor(self):
+        input_data = {"img": MetaTensor([[0, 1], [1, 2]])}
+        result = ConcatItemsd(keys="img", name="cat_img")(input_data)
+        result["cat_img"] += 1
+        torch.testing.assert_allclose(result["img"], torch.tensor([[0, 1], [1, 2]]))
+        torch.testing.assert_allclose(result["cat_img"], torch.tensor([[1, 2], [2, 3]]))
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_concat_itemsd.py::TestConcatItemsd::test_metatensor_values tests/test_concat_itemsd.py::TestConcatItemsd::test_single_metatensor tests/test_concat_itemsd.py::TestConcatItemsd::test_tensor_values tests/test_concat_itemsd.py::TestConcatItemsd::test_numpy_values tests/test_concat_itemsd.py::TestConcatItemsd::test_single_numpy tests/test_concat_itemsd.py::TestConcatItemsd::test_single_tensor
: '>>>>> End Test Output'
git checkout 9c12cd8aab54e31f7c87956ca6fc20573d2148ec -- tests/test_concat_itemsd.py 2>/dev/null || true
