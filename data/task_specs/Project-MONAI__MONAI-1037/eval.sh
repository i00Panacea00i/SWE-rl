#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e82f5dd1b47871106e6d5dc6dcf67f95ff190bfa -- tests/test_load_image.py tests/test_load_imaged.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_load_image.py b/tests/test_load_image.py
--- a/tests/test_load_image.py
+++ b/tests/test_load_image.py
@@ -128,7 +128,7 @@ def test_register(self):
             itk.imwrite(itk_np_view, filename)
 
             loader = LoadImage(image_only=False)
-            loader.register(ITKReader(c_order_axis_indexing=True))
+            loader.register(ITKReader())
             result, header = loader(filename)
             self.assertTupleEqual(tuple(header["spatial_shape"]), expected_shape)
             self.assertTupleEqual(result.shape, spatial_size)
diff --git a/tests/test_load_imaged.py b/tests/test_load_imaged.py
--- a/tests/test_load_imaged.py
+++ b/tests/test_load_imaged.py
@@ -50,7 +50,7 @@ def test_register(self):
             itk.imwrite(itk_np_view, filename)
 
             loader = LoadImaged(keys="img")
-            loader.register(ITKReader(c_order_axis_indexing=True))
+            loader.register(ITKReader())
             result = loader({"img": filename})
             self.assertTupleEqual(tuple(result["img_meta_dict"]["spatial_shape"]), expected_shape)
             self.assertTupleEqual(result["img"].shape, spatial_size)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_load_image.py::TestLoadImage::test_register tests/test_load_imaged.py::TestLoadImaged::test_register tests/test_load_image.py::TestLoadImage::test_nibabel_reader_2 tests/test_load_image.py::TestLoadImage::test_itk_reader_3 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_1 tests/test_load_imaged.py::TestLoadImaged::test_shape_0 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_0 tests/test_load_image.py::TestLoadImage::test_itk_reader_1 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_3 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_4 tests/test_load_image.py::TestLoadImage::test_itk_reader_2 tests/test_load_image.py::TestLoadImage::test_itk_reader_0 tests/test_load_image.py::TestLoadImage::test_kwargs tests/test_load_image.py::TestLoadImage::test_load_png
: '>>>>> End Test Output'
git checkout e82f5dd1b47871106e6d5dc6dcf67f95ff190bfa -- tests/test_load_image.py tests/test_load_imaged.py 2>/dev/null || true
