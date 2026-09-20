#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout b4f8ff10ec94f81feb5967cac418d76b53b7adc2 -- tests/test_load_image.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_load_image.py b/tests/test_load_image.py
--- a/tests/test_load_image.py
+++ b/tests/test_load_image.py
@@ -107,6 +107,18 @@ def get_data(self, _obj):
     (4, 16, 16),
 ]
 
+TEST_CASE_13 = [{"reader": "nibabelreader", "channel_dim": 0}, "test_image.nii.gz", (3, 128, 128, 128)]
+
+TEST_CASE_14 = [{"reader": "nibabelreader", "channel_dim": -1}, "test_image.nii.gz", (128, 128, 128, 3)]
+
+TEST_CASE_15 = [{"reader": "nibabelreader", "channel_dim": 2}, "test_image.nii.gz", (128, 128, 3, 128)]
+
+TEST_CASE_16 = [{"reader": "itkreader", "channel_dim": 0}, "test_image.nii.gz", (3, 128, 128, 128)]
+
+TEST_CASE_17 = [{"reader": "ITKReader", "channel_dim": -1}, "test_image.nii.gz", (128, 128, 128, 3)]
+
+TEST_CASE_18 = [{"reader": "ITKReader", "channel_dim": 2}, "test_image.nii.gz", (128, 128, 3, 128)]
+
 
 class TestLoadImage(unittest.TestCase):
     @parameterized.expand(
@@ -263,6 +275,18 @@ def test_itk_meta(self):
         expected = "Series Description=Routine Brain "
         self.assertEqual(f"{label}={val}", expected)
 
+    @parameterized.expand([TEST_CASE_13, TEST_CASE_14, TEST_CASE_15, TEST_CASE_16, TEST_CASE_17, TEST_CASE_18])
+    def test_channel_dim(self, input_param, filename, expected_shape):
+        test_image = np.random.rand(*expected_shape)
+        with tempfile.TemporaryDirectory() as tempdir:
+            filename = os.path.join(tempdir, filename)
+            nib.save(nib.Nifti1Image(test_image, np.eye(4)), filename)
+            result = LoadImage(**input_param)(filename)
+
+        self.assertTupleEqual(result[0].shape, expected_shape)
+        self.assertTupleEqual(tuple(result[1]["spatial_shape"]), (128, 128, 128))
+        self.assertEqual(result[1]["original_channel_dim"], input_param["channel_dim"])
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_load_image.py::TestLoadImage::test_channel_dim_0 tests/test_load_image.py::TestLoadImage::test_channel_dim_2 tests/test_load_image.py::TestLoadImage::test_channel_dim_1 tests/test_load_image.py::TestLoadImage::test_my_reader tests/test_load_image.py::TestLoadImage::test_nibabel_reader_2 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_6 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_1 tests/test_load_image.py::TestLoadImage::test_itk_dicom_series_reader_1 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_0 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_3 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_4 tests/test_load_image.py::TestLoadImage::test_itk_dicom_series_reader_0 tests/test_load_image.py::TestLoadImage::test_itk_reader_2 tests/test_load_image.py::TestLoadImage::test_itk_dicom_series_reader_2 tests/test_load_image.py::TestLoadImage::test_nibabel_reader_5 tests/test_load_image.py::TestLoadImage::test_itk_reader_0 tests/test_load_image.py::TestLoadImage::test_itk_reader_multichannel tests/test_load_image.py::TestLoadImage::test_itk_meta tests/test_load_image.py::TestLoadImage::test_load_png
: '>>>>> End Test Output'
git checkout b4f8ff10ec94f81feb5967cac418d76b53b7adc2 -- tests/test_load_image.py 2>/dev/null || true
