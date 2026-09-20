#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 34524ee797c98fca7939f4f81e1432288cf823b8 -- pandas/tests/copy_view/test_methods.py pandas/tests/frame/methods/test_select_dtypes.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/copy_view/test_methods.py b/pandas/tests/copy_view/test_methods.py
index cc4c219e6c5d9..df723808ce06b 100644
--- a/pandas/tests/copy_view/test_methods.py
+++ b/pandas/tests/copy_view/test_methods.py
@@ -139,18 +139,16 @@ def test_select_dtypes(using_copy_on_write):
     df2 = df.select_dtypes("int64")
     df2._mgr._verify_integrity()
 
-    # currently this always returns a "view"
-    assert np.shares_memory(get_array(df2, "a"), get_array(df, "a"))
+    if using_copy_on_write:
+        assert np.shares_memory(get_array(df2, "a"), get_array(df, "a"))
+    else:
+        assert not np.shares_memory(get_array(df2, "a"), get_array(df, "a"))
 
     # mutating df2 triggers a copy-on-write for that column/block
     df2.iloc[0, 0] = 0
     if using_copy_on_write:
         assert not np.shares_memory(get_array(df2, "a"), get_array(df, "a"))
-        tm.assert_frame_equal(df, df_orig)
-    else:
-        # but currently select_dtypes() actually returns a view -> mutates parent
-        df_orig.iloc[0, 0] = 0
-        tm.assert_frame_equal(df, df_orig)
+    tm.assert_frame_equal(df, df_orig)
 
 
 def test_to_frame(using_copy_on_write):
diff --git a/pandas/tests/frame/methods/test_select_dtypes.py b/pandas/tests/frame/methods/test_select_dtypes.py
index 6ff5a41b67ec2..9284e0c0cced6 100644
--- a/pandas/tests/frame/methods/test_select_dtypes.py
+++ b/pandas/tests/frame/methods/test_select_dtypes.py
@@ -456,3 +456,12 @@ def test_np_bool_ea_boolean_include_number(self):
         result = df.select_dtypes(include="number")
         expected = DataFrame({"a": [1, 2, 3]})
         tm.assert_frame_equal(result, expected)
+
+    def test_select_dtypes_no_view(self):
+        # https://github.com/pandas-dev/pandas/issues/48090
+        # result of this method is not a view on the original dataframe
+        df = DataFrame({"a": [1, 2, 3], "b": [4, 5, 6]})
+        df_orig = df.copy()
+        result = df.select_dtypes(include=["number"])
+        result.iloc[0, 0] = 0
+        tm.assert_frame_equal(df, df_orig)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail pandas/tests/copy_view/test_methods.py::test_select_dtypes pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_no_view 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_float_dtype[expected0-float]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[exclude-bytes_]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[exclude-unicode]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_numeric[arr1-True]' pandas/tests/copy_view/test_methods.py::test_to_frame pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_bad_arg_raises 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[include-str1]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_bad_datetime64 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[exclude-S1]' pandas/tests/copy_view/test_methods.py::test_rename_columns_modify_parent 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_numeric_nullable_string[string[python]]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_typecodes 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[exclude-str_]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[include-U1]' pandas/tests/copy_view/test_methods.py::test_reindex_columns pandas/tests/copy_view/test_methods.py::test_copy pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_duplicate_columns pandas/tests/copy_view/test_methods.py::test_rename_columns 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_numeric[arr3-False]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[exclude-U1]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_exclude_include_int[include0]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[include-unicode]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_numeric_nullable_string[string[pyarrow]]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_np_bool_ea_boolean_include_number pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_exclude_include_using_list_like 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_exclude_include_int[include1]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_float_dtype[expected1-float]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[include-S1]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_float_dtype[expected2-float32]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[include-str_]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[exclude-str0]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_empty 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_exclude_include_int[include2]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_include_exclude_using_scalars 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[exclude-str1]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_not_an_attr_but_still_valid_dtype pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_include_using_list_like pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_datetime_with_tz 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_float_dtype[expected3-float64]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_exclude_using_list_like 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_numeric[arr2-True]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_include_exclude_mixed_scalars_lists pandas/tests/copy_view/test_methods.py::test_copy_shallow pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_exclude_using_scalars 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[include-bytes_]' pandas/tests/copy_view/test_methods.py::test_reset_index 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_numeric[arr0-True]' 'pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_str_raises[include-str0]' pandas/tests/frame/methods/test_select_dtypes.py::TestSelectDtypes::test_select_dtypes_include_using_scalars
: '>>>>> End Test Output'
git checkout 34524ee797c98fca7939f4f81e1432288cf823b8 -- pandas/tests/copy_view/test_methods.py pandas/tests/frame/methods/test_select_dtypes.py 2>/dev/null || true
