#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout b61dcfbe20981ffca098b7c65fc85e7e38c30bcf -- tests/test_arraydataset.py tests/test_zipdataset.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_arraydataset.py b/tests/test_arraydataset.py
--- a/tests/test_arraydataset.py
+++ b/tests/test_arraydataset.py
@@ -116,7 +116,7 @@ def test_default_none(self, img_transform, expected_shape):
         shutil.rmtree(tempdir)
 
     @parameterized.expand([TEST_CASE_4])
-    def test_dataloading(self, img_transform, expected_shape):
+    def test_dataloading_img(self, img_transform, expected_shape):
         test_image = nib.Nifti1Image(np.random.randint(0, 2, size=(128, 128, 128)), np.eye(4))
         tempdir = tempfile.mkdtemp()
         test_image1 = os.path.join(tempdir, "test_image1.nii.gz")
@@ -135,6 +135,31 @@ def test_dataloading(self, img_transform, expected_shape):
         new_imgs = next(iter(loader))  # test batching
         np.testing.assert_allclose(imgs, new_imgs, atol=1e-3)
 
+    @parameterized.expand([TEST_CASE_4])
+    def test_dataloading_img_label(self, img_transform, expected_shape):
+        test_image = nib.Nifti1Image(np.random.randint(0, 2, size=(128, 128, 128)), np.eye(4))
+        tempdir = tempfile.mkdtemp()
+        test_image1 = os.path.join(tempdir, "test_image1.nii.gz")
+        test_image2 = os.path.join(tempdir, "test_image2.nii.gz")
+        test_label1 = os.path.join(tempdir, "test_label1.nii.gz")
+        test_label2 = os.path.join(tempdir, "test_label2.nii.gz")
+        nib.save(test_image, test_image1)
+        nib.save(test_image, test_image2)
+        nib.save(test_image, test_label1)
+        nib.save(test_image, test_label2)
+        test_images = [test_image1, test_image2]
+        test_labels = [test_label1, test_label2]
+        dataset = ArrayDataset(test_images, img_transform, test_labels, img_transform)
+        self.assertEqual(len(dataset), 2)
+        dataset.set_random_state(1234)
+        loader = DataLoader(dataset, batch_size=10, num_workers=1)
+        data = next(iter(loader))  # test batching
+        np.testing.assert_allclose(data[0].shape, [2] + list(expected_shape))
+
+        dataset.set_random_state(1234)
+        new_data = next(iter(loader))  # test batching
+        np.testing.assert_allclose(data[0], new_data[0], atol=1e-3)
+
 
 if __name__ == "__main__":
     unittest.main()
diff --git a/tests/test_zipdataset.py b/tests/test_zipdataset.py
--- a/tests/test_zipdataset.py
+++ b/tests/test_zipdataset.py
@@ -32,16 +32,16 @@ def __getitem__(self, index):
             return 1, 2, index
 
 
-TEST_CASE_1 = [[Dataset_(5), Dataset_(5), Dataset_(5)], None, [0, 0, 0], 5]
+TEST_CASE_1 = [[Dataset_(5), Dataset_(5), Dataset_(5)], None, (0, 0, 0), 5]
 
-TEST_CASE_2 = [[Dataset_(3), Dataset_(4), Dataset_(5)], None, [0, 0, 0], 3]
+TEST_CASE_2 = [[Dataset_(3), Dataset_(4), Dataset_(5)], None, (0, 0, 0), 3]
 
-TEST_CASE_3 = [[Dataset_(3), Dataset_(4, index_only=False), Dataset_(5)], None, [0, 1, 2, 0, 0], 3]
+TEST_CASE_3 = [[Dataset_(3), Dataset_(4, index_only=False), Dataset_(5)], None, (0, 1, 2, 0, 0), 3]
 
 TEST_CASE_4 = [
     [Dataset_(3), Dataset_(4, index_only=False), Dataset_(5)],
     lambda x: [i + 1 for i in x],
-    [1, 2, 3, 1, 1],
+    (1, 2, 3, 1, 1),
     3,
 ]
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_zipdataset.py::TestZipDataset::test_value_2 tests/test_zipdataset.py::TestZipDataset::test_value_1 tests/test_zipdataset.py::TestZipDataset::test_value_3 tests/test_zipdataset.py::TestZipDataset::test_value_0
: '>>>>> End Test Output'
git checkout b61dcfbe20981ffca098b7c65fc85e7e38c30bcf -- tests/test_arraydataset.py tests/test_zipdataset.py 2>/dev/null || true
