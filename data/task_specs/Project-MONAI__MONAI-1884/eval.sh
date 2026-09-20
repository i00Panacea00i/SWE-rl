#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 76beeb224731e145fe0891aac0fe02e486203ec4 -- tests/test_concat_itemsd.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_concat_itemsd.py b/tests/test_concat_itemsd.py
--- a/tests/test_concat_itemsd.py
+++ b/tests/test_concat_itemsd.py
@@ -38,6 +38,20 @@ def test_numpy_values(self):
         np.testing.assert_allclose(result["img1"], np.array([[0, 1], [1, 2]]))
         np.testing.assert_allclose(result["cat_img"], np.array([[1, 2], [2, 3], [1, 2], [2, 3]]))
 
+    def test_single_numpy(self):
+        input_data = {"img": np.array([[0, 1], [1, 2]])}
+        result = ConcatItemsd(keys="img", name="cat_img")(input_data)
+        result["cat_img"] += 1
+        np.testing.assert_allclose(result["img"], np.array([[0, 1], [1, 2]]))
+        np.testing.assert_allclose(result["cat_img"], np.array([[1, 2], [2, 3]]))
+
+    def test_single_tensor(self):
+        input_data = {"img": torch.tensor([[0, 1], [1, 2]])}
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
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_concat_itemsd.py::TestConcatItemsd::test_single_numpy tests/test_concat_itemsd.py::TestConcatItemsd::test_single_tensor tests/test_concat_itemsd.py::TestConcatItemsd::test_tensor_values tests/test_concat_itemsd.py::TestConcatItemsd::test_numpy_values
: '>>>>> End Test Output'
git checkout 76beeb224731e145fe0891aac0fe02e486203ec4 -- tests/test_concat_itemsd.py 2>/dev/null || true
