#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout fac93503994d21c877cba6844135f1bd9168c061 -- tests/test_copy_itemsd.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_copy_itemsd.py b/tests/test_copy_itemsd.py
--- a/tests/test_copy_itemsd.py
+++ b/tests/test_copy_itemsd.py
@@ -31,12 +31,12 @@
 class TestCopyItemsd(unittest.TestCase):
     @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4])
     def test_numpy_values(self, keys, times, names):
-        input_data = {"img": np.array([[0, 1], [1, 2]]), "seg": np.array([[0, 1], [1, 2]])}
+        input_data = {"img": np.array([[0, 1], [1, 2]]), "seg": np.array([[3, 4], [4, 5]])}
         result = CopyItemsd(keys=keys, times=times, names=names)(input_data)
         for name in ensure_tuple(names):
             self.assertTrue(name in result)
-            result[name] += 1
-            np.testing.assert_allclose(result[name], np.array([[1, 2], [2, 3]]))
+        result["img_1"] += 1
+        np.testing.assert_allclose(result["img_1"], np.array([[1, 2], [2, 3]]))
         np.testing.assert_allclose(result["img"], np.array([[0, 1], [1, 2]]))
 
     def test_tensor_values(self):

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_copy_itemsd.py::TestCopyItemsd::test_numpy_values_1 tests/test_copy_itemsd.py::TestCopyItemsd::test_numpy_values_3 tests/test_copy_itemsd.py::TestCopyItemsd::test_tensor_values tests/test_copy_itemsd.py::TestCopyItemsd::test_numpy_values_2_img tests/test_copy_itemsd.py::TestCopyItemsd::test_numpy_values_0_img tests/test_copy_itemsd.py::TestCopyItemsd::test_graph_tensor_values tests/test_copy_itemsd.py::TestCopyItemsd::test_array_values
: '>>>>> End Test Output'
git checkout fac93503994d21c877cba6844135f1bd9168c061 -- tests/test_copy_itemsd.py 2>/dev/null || true
