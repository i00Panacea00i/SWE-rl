#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 7a5de8b7b9db101a431e70ae2aa8ea7ebb8dfffe -- tests/test_swin_unetr.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_swin_unetr.py b/tests/test_swin_unetr.py
--- a/tests/test_swin_unetr.py
+++ b/tests/test_swin_unetr.py
@@ -16,7 +16,7 @@
 from parameterized import parameterized
 
 from monai.networks import eval_mode
-from monai.networks.nets.swin_unetr import SwinUNETR
+from monai.networks.nets.swin_unetr import PatchMerging, SwinUNETR
 from monai.utils import optional_import
 
 einops, has_einops = optional_import("einops")
@@ -26,26 +26,24 @@
     for in_channels in [1]:
         for depth in [[2, 1, 1, 1], [1, 2, 1, 1]]:
             for out_channels in [2]:
-                for img_size in [64]:
+                for img_size in ((64, 32, 192), (96, 32)):
                     for feature_size in [12]:
                         for norm_name in ["instance"]:
-                            for nd in (2, 3):
-                                test_case = [
-                                    {
-                                        "in_channels": in_channels,
-                                        "out_channels": out_channels,
-                                        "img_size": (img_size,) * nd,
-                                        "feature_size": feature_size,
-                                        "depths": depth,
-                                        "norm_name": norm_name,
-                                        "attn_drop_rate": attn_drop_rate,
-                                    },
-                                    (2, in_channels, *([img_size] * nd)),
-                                    (2, out_channels, *([img_size] * nd)),
-                                ]
-                                if nd == 2:
-                                    test_case[0]["spatial_dims"] = 2  # type: ignore
-                                TEST_CASE_SWIN_UNETR.append(test_case)
+                            test_case = [
+                                {
+                                    "spatial_dims": len(img_size),
+                                    "in_channels": in_channels,
+                                    "out_channels": out_channels,
+                                    "img_size": img_size,
+                                    "feature_size": feature_size,
+                                    "depths": depth,
+                                    "norm_name": norm_name,
+                                    "attn_drop_rate": attn_drop_rate,
+                                },
+                                (2, in_channels, *img_size),
+                                (2, out_channels, *img_size),
+                            ]
+                            TEST_CASE_SWIN_UNETR.append(test_case)
 
 
 class TestSWINUNETR(unittest.TestCase):
@@ -84,6 +82,11 @@ def test_ill_arg(self):
                 drop_rate=0.4,
             )
 
+    def test_patch_merging(self):
+        dim = 10
+        t = PatchMerging(dim)(torch.zeros((1, 21, 20, 20, dim)))
+        self.assertEqual(t.shape, torch.Size([1, 11, 10, 10, 20]))
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_swin_unetr.py::TestSWINUNETR::test_shape_1 tests/test_swin_unetr.py::TestSWINUNETR::test_patch_merging tests/test_swin_unetr.py::TestSWINUNETR::test_shape_3 tests/test_swin_unetr.py::TestSWINUNETR::test_shape_2 tests/test_swin_unetr.py::TestSWINUNETR::test_ill_arg tests/test_swin_unetr.py::TestSWINUNETR::test_shape_0
: '>>>>> End Test Output'
git checkout 7a5de8b7b9db101a431e70ae2aa8ea7ebb8dfffe -- tests/test_swin_unetr.py 2>/dev/null || true
