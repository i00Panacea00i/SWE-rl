#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 541d7abdacb00aaf1c7d0a80aebf0cc204dd571f -- tests/test_patch_wsi_dataset.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_patch_wsi_dataset.py b/tests/test_patch_wsi_dataset.py
--- a/tests/test_patch_wsi_dataset.py
+++ b/tests/test_patch_wsi_dataset.py
@@ -41,6 +41,31 @@
     [{"image": np.array([[[239]], [[239]], [[239]]], dtype=np.uint8), "label": np.array([[[1]]])}],
 ]
 
+TEST_CASE_0_L1 = [
+    {
+        "data": [{"image": FILE_PATH, "location": [0, 0], "label": [1]}],
+        "region_size": (1, 1),
+        "grid_shape": (1, 1),
+        "patch_size": 1,
+        "level": 1,
+        "image_reader_name": "cuCIM",
+    },
+    [{"image": np.array([[[239]], [[239]], [[239]]], dtype=np.uint8), "label": np.array([[[1]]])}],
+]
+
+TEST_CASE_0_L2 = [
+    {
+        "data": [{"image": FILE_PATH, "location": [0, 0], "label": [1]}],
+        "region_size": (1, 1),
+        "grid_shape": (1, 1),
+        "patch_size": 1,
+        "level": 1,
+        "image_reader_name": "cuCIM",
+    },
+    [{"image": np.array([[[239]], [[239]], [[239]]], dtype=np.uint8), "label": np.array([[[1]]])}],
+]
+
+
 TEST_CASE_1 = [
     {
         "data": [{"image": FILE_PATH, "location": [10004, 20004], "label": [0, 0, 0, 1]}],
@@ -57,6 +82,41 @@
     ],
 ]
 
+
+TEST_CASE_1_L0 = [
+    {
+        "data": [{"image": FILE_PATH, "location": [10004, 20004], "label": [0, 0, 0, 1]}],
+        "region_size": (8, 8),
+        "grid_shape": (2, 2),
+        "patch_size": 1,
+        "level": 0,
+        "image_reader_name": "cuCIM",
+    },
+    [
+        {"image": np.array([[[247]], [[245]], [[248]]], dtype=np.uint8), "label": np.array([[[0]]])},
+        {"image": np.array([[[245]], [[247]], [[244]]], dtype=np.uint8), "label": np.array([[[0]]])},
+        {"image": np.array([[[246]], [[246]], [[246]]], dtype=np.uint8), "label": np.array([[[0]]])},
+        {"image": np.array([[[246]], [[246]], [[246]]], dtype=np.uint8), "label": np.array([[[1]]])},
+    ],
+]
+
+
+TEST_CASE_1_L1 = [
+    {
+        "data": [{"image": FILE_PATH, "location": [10004, 20004], "label": [0, 0, 0, 1]}],
+        "region_size": (8, 8),
+        "grid_shape": (2, 2),
+        "patch_size": 1,
+        "level": 1,
+        "image_reader_name": "cuCIM",
+    },
+    [
+        {"image": np.array([[[248]], [[246]], [[249]]], dtype=np.uint8), "label": np.array([[[0]]])},
+        {"image": np.array([[[196]], [[187]], [[192]]], dtype=np.uint8), "label": np.array([[[0]]])},
+        {"image": np.array([[[245]], [[243]], [[244]]], dtype=np.uint8), "label": np.array([[[0]]])},
+        {"image": np.array([[[246]], [[242]], [[243]]], dtype=np.uint8), "label": np.array([[[1]]])},
+    ],
+]
 TEST_CASE_2 = [
     {
         "data": [{"image": FILE_PATH, "location": [0, 0], "label": [1]}],
@@ -90,6 +150,43 @@
     [{"image": np.array([[[239]], [[239]], [[239]]], dtype=np.uint8), "label": np.array([[[1]]])}],
 ]
 
+TEST_CASE_OPENSLIDE_0_L0 = [
+    {
+        "data": [{"image": FILE_PATH, "location": [0, 0], "label": [1]}],
+        "region_size": (1, 1),
+        "grid_shape": (1, 1),
+        "patch_size": 1,
+        "level": 0,
+        "image_reader_name": "OpenSlide",
+    },
+    [{"image": np.array([[[239]], [[239]], [[239]]], dtype=np.uint8), "label": np.array([[[1]]])}],
+]
+
+TEST_CASE_OPENSLIDE_0_L1 = [
+    {
+        "data": [{"image": FILE_PATH, "location": [0, 0], "label": [1]}],
+        "region_size": (1, 1),
+        "grid_shape": (1, 1),
+        "patch_size": 1,
+        "level": 1,
+        "image_reader_name": "OpenSlide",
+    },
+    [{"image": np.array([[[239]], [[239]], [[239]]], dtype=np.uint8), "label": np.array([[[1]]])}],
+]
+
+
+TEST_CASE_OPENSLIDE_0_L2 = [
+    {
+        "data": [{"image": FILE_PATH, "location": [0, 0], "label": [1]}],
+        "region_size": (1, 1),
+        "grid_shape": (1, 1),
+        "patch_size": 1,
+        "level": 2,
+        "image_reader_name": "OpenSlide",
+    },
+    [{"image": np.array([[[239]], [[239]], [[239]]], dtype=np.uint8), "label": np.array([[[1]]])}],
+]
+
 TEST_CASE_OPENSLIDE_1 = [
     {
         "data": [{"image": FILE_PATH, "location": [10004, 20004], "label": [0, 0, 0, 1]}],
@@ -113,7 +210,18 @@ def setUp(self):
         hash_val = testing_data_config("images", FILE_KEY, "hash_val")
         download_url_or_skip_test(FILE_URL, FILE_PATH, hash_type=hash_type, hash_val=hash_val)
 
-    @parameterized.expand([TEST_CASE_0, TEST_CASE_1, TEST_CASE_2, TEST_CASE_3])
+    @parameterized.expand(
+        [
+            TEST_CASE_0,
+            TEST_CASE_0_L1,
+            TEST_CASE_0_L2,
+            TEST_CASE_1,
+            TEST_CASE_1_L0,
+            TEST_CASE_1_L1,
+            TEST_CASE_2,
+            TEST_CASE_3,
+        ]
+    )
     @skipUnless(has_cim, "Requires CuCIM")
     def test_read_patches_cucim(self, input_parameters, expected):
         dataset = PatchWSIDataset(**input_parameters)
@@ -124,7 +232,15 @@ def test_read_patches_cucim(self, input_parameters, expected):
             self.assertIsNone(assert_array_equal(samples[i]["label"], expected[i]["label"]))
             self.assertIsNone(assert_array_equal(samples[i]["image"], expected[i]["image"]))
 
-    @parameterized.expand([TEST_CASE_OPENSLIDE_0, TEST_CASE_OPENSLIDE_1])
+    @parameterized.expand(
+        [
+            TEST_CASE_OPENSLIDE_0,
+            TEST_CASE_OPENSLIDE_0_L0,
+            TEST_CASE_OPENSLIDE_0_L1,
+            TEST_CASE_OPENSLIDE_0_L2,
+            TEST_CASE_OPENSLIDE_1,
+        ]
+    )
     @skipUnless(has_osl, "Requires OpenSlide")
     def test_read_patches_openslide(self, input_parameters, expected):
         dataset = PatchWSIDataset(**input_parameters)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_patch_wsi_dataset.py::TestPatchWSIDataset::test_read_patches_cucim_2 tests/test_patch_wsi_dataset.py::TestPatchWSIDataset::test_read_patches_cucim_4 tests/test_patch_wsi_dataset.py::TestPatchWSIDataset::test_read_patches_cucim_5 tests/test_patch_wsi_dataset.py::TestPatchWSIDataset::test_read_patches_cucim_1 tests/test_patch_wsi_dataset.py::testing_data_config tests/test_patch_wsi_dataset.py::TestPatchWSIDataset::test_read_patches_cucim_3 tests/test_patch_wsi_dataset.py::TestPatchWSIDataset::test_read_patches_cucim_6 tests/test_patch_wsi_dataset.py::TestPatchWSIDataset::test_read_patches_cucim_7 tests/test_patch_wsi_dataset.py::TestPatchWSIDataset::test_read_patches_cucim_0
: '>>>>> End Test Output'
git checkout 541d7abdacb00aaf1c7d0a80aebf0cc204dd571f -- tests/test_patch_wsi_dataset.py 2>/dev/null || true
