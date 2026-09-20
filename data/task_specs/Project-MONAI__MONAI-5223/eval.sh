#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout ba670c9ba78f9f4d76eb12b4d33f245b5774d462 -- tests/test_resized.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_resized.py b/tests/test_resized.py
--- a/tests/test_resized.py
+++ b/tests/test_resized.py
@@ -13,23 +13,44 @@
 
 import numpy as np
 import skimage.transform
+import torch
 from parameterized import parameterized
 
 from monai.data import MetaTensor, set_track_meta
-from monai.transforms import Invertd, Resized
+from monai.transforms import Invertd, Resize, Resized
 from tests.utils import TEST_NDARRAYS_ALL, NumpyImageTestCase2D, assert_allclose, test_local_inversion
 
 TEST_CASE_0 = [{"keys": "img", "spatial_size": 15}, (6, 10, 15)]
 
-TEST_CASE_1 = [{"keys": "img", "spatial_size": 15, "mode": "area"}, (6, 10, 15)]
+TEST_CASE_1 = [
+    {"keys": "img", "spatial_size": 15, "mode": "area", "anti_aliasing": True, "anti_aliasing_sigma": None},
+    (6, 10, 15),
+]
 
-TEST_CASE_2 = [{"keys": "img", "spatial_size": 6, "mode": "trilinear", "align_corners": True}, (2, 4, 6)]
+TEST_CASE_2 = [
+    {"keys": "img", "spatial_size": 6, "mode": "trilinear", "align_corners": True, "anti_aliasing_sigma": 2.0},
+    (2, 4, 6),
+]
 
 TEST_CASE_3 = [
-    {"keys": ["img", "label"], "spatial_size": 6, "mode": ["trilinear", "nearest"], "align_corners": [True, None]},
+    {
+        "keys": ["img", "label"],
+        "spatial_size": 6,
+        "mode": ["trilinear", "nearest"],
+        "align_corners": [True, None],
+        "anti_aliasing": [False, True],
+        "anti_aliasing_sigma": (None, 2.0),
+    },
     (2, 4, 6),
 ]
 
+TEST_CORRECT_CASES = [
+    ((32, -1), "area", False),
+    ((64, 64), "area", True),
+    ((32, 32, 32), "area", True),
+    ((256, 256), "bilinear", False),
+]
+
 
 class TestResized(NumpyImageTestCase2D):
     def test_invalid_inputs(self):
@@ -41,9 +62,9 @@ def test_invalid_inputs(self):
             resize = Resized(keys="img", spatial_size=(128,), mode="order")
             resize({"img": self.imt[0]})
 
-    @parameterized.expand([((32, -1), "area"), ((64, 64), "area"), ((32, 32, 32), "area"), ((256, 256), "bilinear")])
-    def test_correct_results(self, spatial_size, mode):
-        resize = Resized("img", spatial_size, mode=mode)
+    @parameterized.expand(TEST_CORRECT_CASES)
+    def test_correct_results(self, spatial_size, mode, anti_aliasing):
+        resize = Resized("img", spatial_size, mode=mode, anti_aliasing=anti_aliasing)
         _order = 0
         if mode.endswith("linear"):
             _order = 1
@@ -51,7 +72,7 @@ def test_correct_results(self, spatial_size, mode):
             spatial_size = (32, 64)
         expected = [
             skimage.transform.resize(
-                channel, spatial_size, order=_order, clip=False, preserve_range=False, anti_aliasing=False
+                channel, spatial_size, order=_order, clip=False, preserve_range=False, anti_aliasing=anti_aliasing
             )
             for channel in self.imt[0]
         ]
@@ -61,7 +82,7 @@ def test_correct_results(self, spatial_size, mode):
             im = p(self.imt[0])
             out = resize({"img": im})
             test_local_inversion(resize, out, {"img": im}, "img")
-            assert_allclose(out["img"], expected, type_test=False, atol=0.9)
+            assert_allclose(out["img"], expected, type_test=False, atol=1.0)
 
     @parameterized.expand([TEST_CASE_0, TEST_CASE_1, TEST_CASE_2, TEST_CASE_3])
     def test_longest_shape(self, input_param, expected_shape):
@@ -88,6 +109,22 @@ def test_identical_spatial(self):
         transform_inverse = Invertd(keys="Y", transform=xform, orig_keys="X")
         assert_allclose(transform_inverse(out)["Y"].array, np.ones((1, 10, 16, 17)) * 2)
 
+    def test_consistent_resize(self):
+        spatial_size = (16, 16, 16)
+        rescaler_1 = Resize(spatial_size=spatial_size, anti_aliasing=True, anti_aliasing_sigma=(0.5, 1.0, 2.0))
+        rescaler_2 = Resize(spatial_size=spatial_size, anti_aliasing=True, anti_aliasing_sigma=None)
+        rescaler_dict = Resized(
+            keys=["img1", "img2"],
+            spatial_size=spatial_size,
+            anti_aliasing=(True, True),
+            anti_aliasing_sigma=[(0.5, 1.0, 2.0), None],
+        )
+        test_input_1 = torch.randn([3, 32, 32, 32])
+        test_input_2 = torch.randn([3, 32, 32, 32])
+        test_input_dict = {"img1": test_input_1, "img2": test_input_2}
+        assert_allclose(rescaler_1(test_input_1), rescaler_dict(test_input_dict)["img1"])
+        assert_allclose(rescaler_2(test_input_2), rescaler_dict(test_input_dict)["img2"])
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_resized.py::TestResized::test_correct_results_0 tests/test_resized.py::TestResized::test_longest_shape_2 tests/test_resized.py::TestResized::test_correct_results_3 tests/test_resized.py::TestResized::test_correct_results_1 tests/test_resized.py::TestResized::test_longest_shape_3 tests/test_resized.py::TestResized::test_longest_shape_1 tests/test_resized.py::TestResized::test_correct_results_2 tests/test_resized.py::TestResized::test_consistent_resize tests/test_resized.py::TestResized::test_identical_spatial tests/test_resized.py::TestResized::test_invalid_inputs tests/test_resized.py::TestResized::test_longest_shape_0
: '>>>>> End Test Output'
git checkout ba670c9ba78f9f4d76eb12b4d33f245b5774d462 -- tests/test_resized.py 2>/dev/null || true
