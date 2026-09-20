#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 05d12b5eb9ef3ef0ef697dac92e3548371b6dcd1 -- pandas/tests/resample/test_resampler_grouper.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/resample/test_resampler_grouper.py b/pandas/tests/resample/test_resampler_grouper.py
index 3ab57e137f1c1..c3717cee05f2b 100644
--- a/pandas/tests/resample/test_resampler_grouper.py
+++ b/pandas/tests/resample/test_resampler_grouper.py
@@ -536,3 +536,82 @@ def test_groupby_resample_size_all_index_same():
         ),
     )
     tm.assert_series_equal(result, expected)
+
+
+def test_groupby_resample_on_index_with_list_of_keys():
+    # GH 50840
+    df = DataFrame(
+        data={
+            "group": [0, 0, 0, 0, 1, 1, 1, 1],
+            "val": [3, 1, 4, 1, 5, 9, 2, 6],
+        },
+        index=Series(
+            date_range(start="2016-01-01", periods=8),
+            name="date",
+        ),
+    )
+    result = df.groupby("group").resample("2D")[["val"]].mean()
+    expected = DataFrame(
+        data={
+            "val": [2.0, 2.5, 7.0, 4.0],
+        },
+        index=Index(
+            data=[
+                (0, Timestamp("2016-01-01")),
+                (0, Timestamp("2016-01-03")),
+                (1, Timestamp("2016-01-05")),
+                (1, Timestamp("2016-01-07")),
+            ],
+            name=("group", "date"),
+        ),
+    )
+    tm.assert_frame_equal(result, expected)
+
+
+def test_groupby_resample_on_index_with_list_of_keys_multi_columns():
+    # GH 50876
+    df = DataFrame(
+        data={
+            "group": [0, 0, 0, 0, 1, 1, 1, 1],
+            "first_val": [3, 1, 4, 1, 5, 9, 2, 6],
+            "second_val": [2, 7, 1, 8, 2, 8, 1, 8],
+            "third_val": [1, 4, 1, 4, 2, 1, 3, 5],
+        },
+        index=Series(
+            date_range(start="2016-01-01", periods=8),
+            name="date",
+        ),
+    )
+    result = df.groupby("group").resample("2D")[["first_val", "second_val"]].mean()
+    expected = DataFrame(
+        data={
+            "first_val": [2.0, 2.5, 7.0, 4.0],
+            "second_val": [4.5, 4.5, 5.0, 4.5],
+        },
+        index=Index(
+            data=[
+                (0, Timestamp("2016-01-01")),
+                (0, Timestamp("2016-01-03")),
+                (1, Timestamp("2016-01-05")),
+                (1, Timestamp("2016-01-07")),
+            ],
+            name=("group", "date"),
+        ),
+    )
+    tm.assert_frame_equal(result, expected)
+
+
+def test_groupby_resample_on_index_with_list_of_keys_missing_column():
+    # GH 50876
+    df = DataFrame(
+        data={
+            "group": [0, 0, 0, 0, 1, 1, 1, 1],
+            "val": [3, 1, 4, 1, 5, 9, 2, 6],
+        },
+        index=Series(
+            date_range(start="2016-01-01", periods=8),
+            name="date",
+        ),
+    )
+    with pytest.raises(KeyError, match="Columns not found"):
+        df.groupby("group").resample("2D")[["val_not_in_dataframe"]].mean()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail pandas/tests/resample/test_resampler_grouper.py::test_groupby_resample_on_index_with_list_of_keys pandas/tests/resample/test_resampler_grouper.py::test_groupby_resample_on_index_with_list_of_keys_multi_columns pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_agg_listlike 'pandas/tests/resample/test_resampler_grouper.py::test_methods[sum]' pandas/tests/resample/test_resampler_grouper.py::test_deferred_with_groupby pandas/tests/resample/test_resampler_grouper.py::test_groupby_with_origin pandas/tests/resample/test_resampler_grouper.py::test_methods_nunique pandas/tests/resample/test_resampler_grouper.py::test_consistency_with_window pandas/tests/resample/test_resampler_grouper.py::test_tab_complete_ipython6_warning 'pandas/tests/resample/test_resampler_grouper.py::test_empty[keys0]' pandas/tests/resample/test_resampler_grouper.py::test_getitem pandas/tests/resample/test_resampler_grouper.py::test_groupby_resample_on_index_with_list_of_keys_missing_column 'pandas/tests/resample/test_resampler_grouper.py::test_methods[nearest]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[median]' pandas/tests/resample/test_resampler_grouper.py::test_apply pandas/tests/resample/test_resampler_grouper.py::test_groupby_resample_on_api_with_getitem 'pandas/tests/resample/test_resampler_grouper.py::test_methods[last]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods_std_var[var]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[ohlc]' pandas/tests/resample/test_resampler_grouper.py::test_apply_to_one_column_of_df 'pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_agg_object_dtype_all_nan[False]' pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_agg 'pandas/tests/resample/test_resampler_grouper.py::test_empty[keys1]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[mean]' pandas/tests/resample/test_resampler_grouper.py::test_groupby_resample_with_list_of_keys 'pandas/tests/resample/test_resampler_grouper.py::test_methods[asfreq]' 'pandas/tests/resample/test_resampler_grouper.py::test_resample_empty_Dataframe[keys0]' pandas/tests/resample/test_resampler_grouper.py::test_apply_with_mutated_index pandas/tests/resample/test_resampler_grouper.py::test_getitem_multiple pandas/tests/resample/test_resampler_grouper.py::test_median_duplicate_columns 'pandas/tests/resample/test_resampler_grouper.py::test_resample_empty_Dataframe[keys1]' pandas/tests/resample/test_resampler_grouper.py::test_groupby_resample_size_all_index_same pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_with_label 'pandas/tests/resample/test_resampler_grouper.py::test_methods_std_var[std]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[min]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[sem]' 'pandas/tests/resample/test_resampler_grouper.py::test_resample_groupby_agg_object_dtype_all_nan[True]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[size]' pandas/tests/resample/test_resampler_grouper.py::test_nearest 'pandas/tests/resample/test_resampler_grouper.py::test_methods[count]' pandas/tests/resample/test_resampler_grouper.py::test_apply_columns_multilevel 'pandas/tests/resample/test_resampler_grouper.py::test_methods[first]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[ffill]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[max]' 'pandas/tests/resample/test_resampler_grouper.py::test_methods[bfill]'
: '>>>>> End Test Output'
git checkout 05d12b5eb9ef3ef0ef697dac92e3548371b6dcd1 -- pandas/tests/resample/test_resampler_grouper.py 2>/dev/null || true
