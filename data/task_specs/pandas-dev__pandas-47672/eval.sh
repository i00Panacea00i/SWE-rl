#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e6024c12f0061602b67f64adcaf8ab5cb77d5418 -- pandas/tests/resample/test_resampler_grouper.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/resample/test_resampler_grouper.py b/pandas/tests/resample/test_resampler_grouper.py
index ceb9d6e2fda4d..7fe1e645aa141 100644
--- a/pandas/tests/resample/test_resampler_grouper.py
+++ b/pandas/tests/resample/test_resampler_grouper.py
@@ -435,7 +435,11 @@ def test_empty(keys):
     # GH 26411
     df = DataFrame([], columns=["a", "b"], index=TimedeltaIndex([]))
     result = df.groupby(keys).resample(rule=pd.to_timedelta("00:00:01")).mean()
-    expected = DataFrame(columns=["a", "b"]).set_index(keys, drop=False)
+    expected = (
+        DataFrame(columns=["a", "b"])
+        .set_index(keys, drop=False)
+        .set_index(TimedeltaIndex([]), append=True)
+    )
     if len(keys) == 1:
         expected.index.name = keys[0]
 
@@ -497,3 +501,19 @@ def test_groupby_resample_with_list_of_keys():
         ),
     )
     tm.assert_frame_equal(result, expected)
+
+
+@pytest.mark.parametrize("keys", [["a"], ["a", "b"]])
+def test_resample_empty_Dataframe(keys):
+    # GH 47705
+    df = DataFrame([], columns=["a", "b", "date"])
+    df["date"] = pd.to_datetime(df["date"])
+    df = df.set_index("date")
+    result = df.groupby(keys).resample(rule=pd.to_timedelta("00:00:01")).mean()
+    expected = DataFrame(columns=["a", "b", "date"]).set_index(keys, drop=False)
+    expected["date"] = pd.to_datetime(expected["date"])
+    expected = expected.set_index("date", append=True, drop=True)
+    if len(keys) == 1:
+        expected.index.name = keys[0]
+
+    tm.assert_frame_equal(result, expected)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'pandas/tests/resample/test_resampler_grouper.py::test_resample_empty_Dataframe[keys1]' 'pandas/tests/resample/test_resampler_grouper.py::test_resample_empty_Dataframe[keys0]' 'pandas/tests/resample/test_resampler_grouper.py::test_empty[keys0]' 'pandas/tests/resample/test_resampler_grouper.py::test_empty[keys1]' pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_agg_listlike 'pandas/tests/resample/test_resampler_grouper.py::test_methods[sum]' pandas/tests/resample/test_resampler_grouper.py::test_deferred_with_groupby pandas/tests/resample/test_resampler_grouper.py::test_groupby_with_origin pandas/tests/resample/test_resampler_grouper.py::test_methods_nunique pandas/tests/resample/test_resampler_grouper.py::test_consistency_with_window pandas/tests/resample/test_resampler_grouper.py::test_tab_complete_ipython6_warning pandas/tests/resample/test_resampler_grouper.py::test_getitem 'pandas/tests/resample/test_resampler_grouper.py::test_methods[median]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[nearest]' pandas/tests/resample/test_resampler_grouper.py::test_apply pandas/tests/resample/test_resampler_grouper.py::test_groupby_resample_on_api_with_getitem 'pandas/tests/resample/test_resampler_grouper.py::test_methods[last]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods_std_var[var]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[ohlc]' pandas/tests/resample/test_resampler_grouper.py::test_apply_to_one_column_of_df 'pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_agg_object_dtype_all_nan[False]' pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_agg 'pandas/tests/resample/test_resampler_grouper.py::test_methods[mean]' pandas/tests/resample/test_resampler_grouper.py::test_groupby_resample_with_list_of_keys 'pandas/tests/resample/test_resampler_grouper.py::test_methods[asfreq]' pandas/tests/resample/test_resampler_grouper.py::test_apply_with_mutated_index pandas/tests/resample/test_resampler_grouper.py::test_getitem_multiple pandas/tests/resample/test_resampler_grouper.py::test_median_duplicate_columns pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_with_label 'pandas/tests/resample/test_resampler_grouper.py::test_methods_std_var[std]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[min]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[sem]' 'pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_agg_object_dtype_all_nan[True]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[size]' pandas/tests/resample/test_resampler_grouper.py::test_nearest 'pandas/tests/resample/test_resampler_grouper.py::test_methods[count]' pandas/tests/resample/test_resampler_grouper.py::test_apply_columns_multilevel 'pandas/tests/resample/test_resampler_grouper.py::test_methods[first]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[ffill]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[max]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[bfill]'
: '>>>>> End Test Output'
git checkout e6024c12f0061602b67f64adcaf8ab5cb77d5418 -- pandas/tests/resample/test_resampler_grouper.py 2>/dev/null || true
