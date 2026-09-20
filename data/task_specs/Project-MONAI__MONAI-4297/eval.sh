#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout fdec959cc2fbe9f09ed8d95a26bf24a206de8113 -- tests/test_grid_dataset.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_grid_dataset.py b/tests/test_grid_dataset.py
--- a/tests/test_grid_dataset.py
+++ b/tests/test_grid_dataset.py
@@ -60,20 +60,20 @@ def test_loading_array(self):
             np.testing.assert_equal(tuple(item[0].shape), (2, 1, 2, 2))
         np.testing.assert_allclose(
             item[0],
-            np.array([[[[1.4965, 2.4965], [5.4965, 6.4965]]], [[[11.3584, 12.3584], [15.3584, 16.3584]]]]),
+            np.array([[[[7.4965, 8.4965], [11.4965, 12.4965]]], [[[11.3584, 12.3584], [15.3584, 16.3584]]]]),
             rtol=1e-4,
         )
-        np.testing.assert_allclose(item[1], np.array([[[0, 1], [0, 2], [2, 4]], [[0, 1], [2, 4], [2, 4]]]), rtol=1e-5)
+        np.testing.assert_allclose(item[1], np.array([[[0, 1], [2, 4], [0, 2]], [[0, 1], [2, 4], [2, 4]]]), rtol=1e-5)
         if sys.platform != "win32":
             for item in DataLoader(ds, batch_size=2, shuffle=False, num_workers=2):
                 np.testing.assert_equal(tuple(item[0].shape), (2, 1, 2, 2))
             np.testing.assert_allclose(
                 item[0],
-                np.array([[[[1.2548, 2.2548], [5.2548, 6.2548]]], [[[9.1106, 10.1106], [13.1106, 14.1106]]]]),
+                np.array([[[[7.2548, 8.2548], [11.2548, 12.2548]]], [[[9.1106, 10.1106], [13.1106, 14.1106]]]]),
                 rtol=1e-3,
             )
             np.testing.assert_allclose(
-                item[1], np.array([[[0, 1], [0, 2], [2, 4]], [[0, 1], [2, 4], [2, 4]]]), rtol=1e-5
+                item[1], np.array([[[0, 1], [2, 4], [0, 2]], [[0, 1], [2, 4], [2, 4]]]), rtol=1e-5
             )
 
     def test_loading_dict(self):
@@ -102,20 +102,20 @@ def test_loading_dict(self):
             self.assertListEqual(item[0]["metadata"], ["test string", "test string"])
         np.testing.assert_allclose(
             item[0]["image"],
-            np.array([[[[1.4965, 2.4965], [5.4965, 6.4965]]], [[[11.3584, 12.3584], [15.3584, 16.3584]]]]),
+            np.array([[[[7.4965, 8.4965], [11.4965, 12.4965]]], [[[11.3584, 12.3584], [15.3584, 16.3584]]]]),
             rtol=1e-4,
         )
-        np.testing.assert_allclose(item[1], np.array([[[0, 1], [0, 2], [2, 4]], [[0, 1], [2, 4], [2, 4]]]), rtol=1e-5)
+        np.testing.assert_allclose(item[1], np.array([[[0, 1], [2, 4], [0, 2]], [[0, 1], [2, 4], [2, 4]]]), rtol=1e-5)
         if sys.platform != "win32":
             for item in DataLoader(ds, batch_size=2, shuffle=False, num_workers=2):
                 np.testing.assert_equal(item[0]["image"].shape, (2, 1, 2, 2))
             np.testing.assert_allclose(
                 item[0]["image"],
-                np.array([[[[1.2548, 2.2548], [5.2548, 6.2548]]], [[[9.1106, 10.1106], [13.1106, 14.1106]]]]),
+                np.array([[[[7.2548, 8.2548], [11.2548, 12.2548]]], [[[9.1106, 10.1106], [13.1106, 14.1106]]]]),
                 rtol=1e-3,
             )
             np.testing.assert_allclose(
-                item[1], np.array([[[0, 1], [0, 2], [2, 4]], [[0, 1], [2, 4], [2, 4]]]), rtol=1e-5
+                item[1], np.array([[[0, 1], [2, 4], [0, 2]], [[0, 1], [2, 4], [2, 4]]]), rtol=1e-5
             )
 
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_grid_dataset.py::TestGridPatchDataset::test_loading_dict tests/test_grid_dataset.py::TestGridPatchDataset::test_loading_array tests/test_grid_dataset.py::TestGridPatchDataset::test_shape
: '>>>>> End Test Output'
git checkout fdec959cc2fbe9f09ed8d95a26bf24a206de8113 -- tests/test_grid_dataset.py 2>/dev/null || true
