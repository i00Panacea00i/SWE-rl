#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout a8ff27c6a829d42a240446da2324c3967b28ba7f -- tests/test_copy_itemsd.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_copy_itemsd.py b/tests/test_copy_itemsd.py
--- a/tests/test_copy_itemsd.py
+++ b/tests/test_copy_itemsd.py
@@ -39,13 +39,20 @@ def test_numpy_values(self, keys, times, names):
         np.testing.assert_allclose(result["img_1"], np.array([[1, 2], [2, 3]]))
         np.testing.assert_allclose(result["img"], np.array([[0, 1], [1, 2]]))
 
+    def test_default_names(self):
+        input_data = {"img": np.array([[0, 1], [1, 2]]), "seg": np.array([[3, 4], [4, 5]])}
+        result = CopyItemsd(keys=["img", "seg"], times=2, names=None)(input_data)
+        for name in ["img_0", "seg_0", "img_1", "seg_1"]:
+            self.assertTrue(name in result)
+
     def test_tensor_values(self):
         device = torch.device("cuda:0") if torch.cuda.is_available() else torch.device("cpu:0")
         input_data = {
             "img": torch.tensor([[0, 1], [1, 2]], device=device),
             "seg": torch.tensor([[0, 1], [1, 2]], device=device),
         }
-        result = CopyItemsd(keys="img", times=1, names="img_1")(input_data)
+        # test default `times=1`
+        result = CopyItemsd(keys="img", names="img_1")(input_data)
         self.assertTrue("img_1" in result)
         result["img_1"] += 1
         torch.testing.assert_allclose(result["img"], torch.tensor([[0, 1], [1, 2]], device=device))

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_copy_itemsd.py::TestCopyItemsd::test_tensor_values tests/test_copy_itemsd.py::TestCopyItemsd::test_default_names tests/test_copy_itemsd.py::TestCopyItemsd::test_numpy_values_1 tests/test_copy_itemsd.py::TestCopyItemsd::test_array_values tests/test_copy_itemsd.py::TestCopyItemsd::test_numpy_values_2_img tests/test_copy_itemsd.py::TestCopyItemsd::test_numpy_values_0_img tests/test_copy_itemsd.py::TestCopyItemsd::test_graph_tensor_values tests/test_copy_itemsd.py::TestCopyItemsd::test_numpy_values_3
: '>>>>> End Test Output'
git checkout a8ff27c6a829d42a240446da2324c3967b28ba7f -- tests/test_copy_itemsd.py 2>/dev/null || true
