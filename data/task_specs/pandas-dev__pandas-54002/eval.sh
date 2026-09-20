#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 172b7c116a66c63bed605c633683778f828d2e57 -- pandas/tests/indexing/test_partial.py pandas/tests/series/indexing/test_datetime.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/indexing/test_partial.py b/pandas/tests/indexing/test_partial.py
index 5d1d4ba6f638a..bc6e8aed449f3 100644
--- a/pandas/tests/indexing/test_partial.py
+++ b/pandas/tests/indexing/test_partial.py
@@ -664,5 +664,14 @@ def test_slice_irregular_datetime_index_with_nan(self):
         index = pd.to_datetime(["2012-01-01", "2012-01-02", "2012-01-03", None])
         df = DataFrame(range(len(index)), index=index)
         expected = DataFrame(range(len(index[:3])), index=index[:3])
-        result = df["2012-01-01":"2012-01-04"]
+        with pytest.raises(KeyError, match="non-existing keys is not allowed"):
+            # Upper bound is not in index (which is unordered)
+            # GH53983
+            # GH37819
+            df["2012-01-01":"2012-01-04"]
+        # Need this precision for right bound since the right slice
+        # bound is "rounded" up to the largest timepoint smaller than
+        # the next "resolution"-step of the provided point.
+        # e.g. 2012-01-03 is rounded up to 2012-01-04 - 1ns
+        result = df["2012-01-01":"2012-01-03 00:00:00.000000000"]
         tm.assert_frame_equal(result, expected)
diff --git a/pandas/tests/series/indexing/test_datetime.py b/pandas/tests/series/indexing/test_datetime.py
index f47e344336a8b..072607c29fd4c 100644
--- a/pandas/tests/series/indexing/test_datetime.py
+++ b/pandas/tests/series/indexing/test_datetime.py
@@ -384,15 +384,19 @@ def compare(slobj):
         expected.index = expected.index._with_freq(None)
         tm.assert_series_equal(result, expected)
 
-    compare(slice("2011-01-01", "2011-01-15"))
-    with pytest.raises(KeyError, match="Value based partial slicing on non-monotonic"):
-        compare(slice("2010-12-30", "2011-01-15"))
-    compare(slice("2011-01-01", "2011-01-16"))
-
-    # partial ranges
-    compare(slice("2011-01-01", "2011-01-6"))
-    compare(slice("2011-01-06", "2011-01-8"))
-    compare(slice("2011-01-06", "2011-01-12"))
+    for key in [
+        slice("2011-01-01", "2011-01-15"),
+        slice("2010-12-30", "2011-01-15"),
+        slice("2011-01-01", "2011-01-16"),
+        # partial ranges
+        slice("2011-01-01", "2011-01-6"),
+        slice("2011-01-06", "2011-01-8"),
+        slice("2011-01-06", "2011-01-12"),
+    ]:
+        with pytest.raises(
+            KeyError, match="Value based partial slicing on non-monotonic"
+        ):
+            compare(key)
 
     # single values
     result = ts2["2011"].sort_index()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail pandas/tests/indexing/test_partial.py::TestStringSlicing::test_slice_irregular_datetime_index_with_nan pandas/tests/series/indexing/test_datetime.py::test_indexing_unordered pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_loc_setitem_zerolen_list_length_must_match_columns pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_empty_frame_setitem_index_name_retained pandas/tests/indexing/test_partial.py::TestPartialSetting::test_partial_setting_frame 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes_missing_value[idx0-labels0]' pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame pandas/tests/indexing/test_partial.py::TestPartialSetting::test_partial_set_invalid pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_loc_setitem_zerolen_series_columns_align pandas/tests/series/indexing/test_datetime.py::test_indexing 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes_not_matched_type[idx2-labels2-None' pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_empty_frame_setitem_index_name_inherited 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes[Series-idx0-labels0-expected_idx0]' pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame5 pandas/tests/series/indexing/test_datetime.py::test_fancy_getitem pandas/tests/series/indexing/test_datetime.py::test_getitem_str_second_with_datetimeindex pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame3 pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame_empty_consistencies pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame2 pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame_no_index pandas/tests/series/indexing/test_datetime.py::test_fancy_setitem pandas/tests/series/indexing/test_datetime.py::test_getitem_setitem_periodindex pandas/tests/series/indexing/test_datetime.py::test_getitem_setitem_datetimeindex pandas/tests/indexing/test_partial.py::TestPartialSetting::test_series_partial_set 'pandas/tests/series/indexing/test_datetime.py::test_getitem_setitem_datetime_tz[pytz]' pandas/tests/indexing/test_partial.py::TestPartialSetting::test_partial_setting 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes[DataFrame-idx0-labels0-expected_idx0]' pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame_set_series pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame4 pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame_empty_copy_assignment 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes_not_matched_type[idx0-labels0-None' 'pandas/tests/series/indexing/test_datetime.py::test_getitem_setitem_datetime_tz[dateutil]' pandas/tests/series/indexing/test_datetime.py::test_getitem_str_month_with_datetimeindex pandas/tests/series/indexing/test_datetime.py::test_indexing_unordered2 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes[Series-idx1-labels1-expected_idx1]' 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes_missing_value[idx2-labels2]' pandas/tests/indexing/test_partial.py::TestPartialSetting::test_partial_setting2 pandas/tests/series/indexing/test_datetime.py::test_datetime_indexing pandas/tests/series/indexing/test_datetime.py::test_indexing_with_duplicate_datetimeindex pandas/tests/indexing/test_partial.py::TestEmptyFrameSetitemExpansion::test_partial_set_empty_frame_row 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes[DataFrame-idx2-labels2-expected_idx2]' pandas/tests/series/indexing/test_datetime.py::test_indexing_over_size_cutoff_period_index 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes_missing_value[idx1-labels1]' pandas/tests/series/indexing/test_datetime.py::test_loc_getitem_over_size_cutoff 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_setitem_with_expansion_numeric_into_datetimeindex[100]' 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes_not_matched_type[idx1-labels1-None' 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes[Series-idx2-labels2-expected_idx2]' pandas/tests/indexing/test_partial.py::TestPartialSetting::test_series_partial_set_with_name 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_loc_with_list_of_strings_representing_datetimes[DataFrame-idx1-labels1-expected_idx1]' pandas/tests/indexing/test_partial.py::TestPartialSetting::test_partial_setting_mixed_dtype pandas/tests/series/indexing/test_datetime.py::test_getitem_str_year_with_datetimeindex 'pandas/tests/indexing/test_partial.py::TestPartialSetting::test_setitem_with_expansion_numeric_into_datetimeindex[100.0]'
: '>>>>> End Test Output'
git checkout 172b7c116a66c63bed605c633683778f828d2e57 -- pandas/tests/indexing/test_partial.py pandas/tests/series/indexing/test_datetime.py 2>/dev/null || true
