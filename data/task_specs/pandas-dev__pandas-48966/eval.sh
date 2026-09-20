#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout c671f6ca3dba3f4e6f3077c00c1ff773d1ef7f45 -- pandas/tests/frame/methods/test_compare.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/frame/methods/test_compare.py b/pandas/tests/frame/methods/test_compare.py
index 55e5db9603fe5..2c47285d7c507 100644
--- a/pandas/tests/frame/methods/test_compare.py
+++ b/pandas/tests/frame/methods/test_compare.py
@@ -238,17 +238,51 @@ def test_invalid_input_result_names(result_names):
         df1.compare(df2, result_names=result_names)
 
 
-def test_compare_ea_and_np_dtype():
-    # GH#44014
-    df1 = pd.DataFrame({"a": [4.0, 4], "b": [1.0, 2]})
-    df2 = pd.DataFrame({"a": pd.Series([1, pd.NA], dtype="Int64"), "b": [1.0, 2]})
+@pytest.mark.parametrize(
+    "val1,val2",
+    [(4, pd.NA), (pd.NA, pd.NA), (pd.NA, 4)],
+)
+def test_compare_ea_and_np_dtype(val1, val2):
+    # GH 48966
+    arr = [4.0, val1]
+    ser = pd.Series([1, val2], dtype="Int64")
+
+    df1 = pd.DataFrame({"a": arr, "b": [1.0, 2]})
+    df2 = pd.DataFrame({"a": ser, "b": [1.0, 2]})
+    expected = pd.DataFrame(
+        {
+            ("a", "self"): arr,
+            ("a", "other"): ser,
+            ("b", "self"): np.nan,
+            ("b", "other"): np.nan,
+        }
+    )
     result = df1.compare(df2, keep_shape=True)
+    tm.assert_frame_equal(result, expected)
+
+
+@pytest.mark.parametrize(
+    "df1_val,df2_val,diff_self,diff_other",
+    [
+        (4, 3, 4, 3),
+        (4, 4, pd.NA, pd.NA),
+        (4, pd.NA, 4, pd.NA),
+        (pd.NA, pd.NA, pd.NA, pd.NA),
+    ],
+)
+def test_compare_nullable_int64_dtype(df1_val, df2_val, diff_self, diff_other):
+    # GH 48966
+    df1 = pd.DataFrame({"a": pd.Series([df1_val, pd.NA], dtype="Int64"), "b": [1.0, 2]})
+    df2 = df1.copy()
+    df2.loc[0, "a"] = df2_val
+
     expected = pd.DataFrame(
         {
-            ("a", "self"): [4.0, np.nan],
-            ("a", "other"): pd.Series([1, pd.NA], dtype="Int64"),
+            ("a", "self"): pd.Series([diff_self, pd.NA], dtype="Int64"),
+            ("a", "other"): pd.Series([diff_other, pd.NA], dtype="Int64"),
             ("b", "self"): np.nan,
             ("b", "other"): np.nan,
         }
     )
+    result = df1.compare(df2, keep_shape=True)
     tm.assert_frame_equal(result, expected)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'pandas/tests/frame/methods/test_compare.py::test_compare_ea_and_np_dtype[4-val20]' 'pandas/tests/frame/methods/test_compare.py::test_compare_nullable_int64_dtype[4-df2_val2-4-diff_other2]' 'pandas/tests/frame/methods/test_compare.py::test_compare_multi_index[0]' 'pandas/tests/frame/methods/test_compare.py::test_invalid_input_result_names[HK]' 'pandas/tests/frame/methods/test_compare.py::test_compare_ea_and_np_dtype[val11-val21]' 'pandas/tests/frame/methods/test_compare.py::test_compare_multi_index[1]' 'pandas/tests/frame/methods/test_compare.py::test_compare_nullable_int64_dtype[4-4-diff_self1-diff_other1]' 'pandas/tests/frame/methods/test_compare.py::test_compare_axis[index]' pandas/tests/frame/methods/test_compare.py::test_compare_with_equal_nulls 'pandas/tests/frame/methods/test_compare.py::test_compare_nullable_int64_dtype[4-3-4-3]' 'pandas/tests/frame/methods/test_compare.py::test_invalid_input_result_names[3.0]' 'pandas/tests/frame/methods/test_compare.py::test_compare_axis[1]' 'pandas/tests/frame/methods/test_compare.py::test_compare_axis[0]' 'pandas/tests/frame/methods/test_compare.py::test_compare_various_formats[False-True]' 'pandas/tests/frame/methods/test_compare.py::test_invalid_input_result_names[result_names0]' 'pandas/tests/frame/methods/test_compare.py::test_compare_ea_and_np_dtype[val12-4]' 'pandas/tests/frame/methods/test_compare.py::test_compare_nullable_int64_dtype[df1_val3-df2_val3-diff_self3-diff_other3]' pandas/tests/frame/methods/test_compare.py::test_compare_unaligned_objects 'pandas/tests/frame/methods/test_compare.py::test_compare_axis[columns]' 'pandas/tests/frame/methods/test_compare.py::test_invalid_input_result_names[result_names2]' 'pandas/tests/frame/methods/test_compare.py::test_invalid_input_result_names[3]' 'pandas/tests/frame/methods/test_compare.py::test_compare_various_formats[True-False]' 'pandas/tests/frame/methods/test_compare.py::test_compare_various_formats[True-True]' pandas/tests/frame/methods/test_compare.py::test_compare_result_names pandas/tests/frame/methods/test_compare.py::test_compare_with_non_equal_nulls
: '>>>>> End Test Output'
git checkout c671f6ca3dba3f4e6f3077c00c1ff773d1ef7f45 -- pandas/tests/frame/methods/test_compare.py 2>/dev/null || true
