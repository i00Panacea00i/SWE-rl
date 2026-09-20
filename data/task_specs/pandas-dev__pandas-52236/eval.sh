#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 32f789fbc5d5a72d9d1ac14935635289eeac9009 -- pandas/tests/groupby/test_min_max.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/groupby/test_min_max.py b/pandas/tests/groupby/test_min_max.py
index 8602f8bdb1aa1..37eb52be0b37b 100644
--- a/pandas/tests/groupby/test_min_max.py
+++ b/pandas/tests/groupby/test_min_max.py
@@ -247,3 +247,26 @@ def test_min_max_nullable_uint64_empty_group():
     res = gb.max()
     expected.iloc[0, 0] = 9
     tm.assert_frame_equal(res, expected)
+
+
+@pytest.mark.parametrize("func", ["first", "last", "min", "max"])
+def test_groupby_min_max_categorical(func):
+    # GH: 52151
+    df = DataFrame(
+        {
+            "col1": pd.Categorical(["A"], categories=list("AB"), ordered=True),
+            "col2": pd.Categorical([1], categories=[1, 2], ordered=True),
+            "value": 0.1,
+        }
+    )
+    result = getattr(df.groupby("col1", observed=False), func)()
+
+    idx = pd.CategoricalIndex(data=["A", "B"], name="col1", ordered=True)
+    expected = DataFrame(
+        {
+            "col2": pd.Categorical([1, None], categories=[1, 2], ordered=True),
+            "value": [0.1, None],
+        },
+        index=idx,
+    )
+    tm.assert_frame_equal(result, expected)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_categorical[min]' 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_categorical[last]' 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_categorical[first]' 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_categorical[max]' pandas/tests/groupby/test_min_max.py::test_max_min_object_multiple_columns 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_nullable[Float32]' 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_nullable[Float64]' 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_nullable[Int32]' 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_nullable[boolean]' 'pandas/tests/groupby/test_min_max.py::test_groupby_aggregate_period_frame[min]' 'pandas/tests/groupby/test_min_max.py::test_aggregate_categorical_lost_index[min]' 'pandas/tests/groupby/test_min_max.py::test_groupby_aggregate_period_frame[max]' pandas/tests/groupby/test_min_max.py::test_max_min_non_numeric pandas/tests/groupby/test_min_max.py::test_max_inat_not_all_na 'pandas/tests/groupby/test_min_max.py::test_aggregate_categorical_lost_index[max]' 'pandas/tests/groupby/test_min_max.py::test_groupby_min_max_nullable[Int64]' pandas/tests/groupby/test_min_max.py::test_min_max_nullable_uint64_empty_group pandas/tests/groupby/test_min_max.py::test_min_date_with_nans pandas/tests/groupby/test_min_max.py::test_max_inat 'pandas/tests/groupby/test_min_max.py::test_groupby_aggregate_period_column[max]' 'pandas/tests/groupby/test_min_max.py::test_groupby_aggregate_period_column[min]' pandas/tests/groupby/test_min_max.py::test_aggregate_numeric_object_dtype
: '>>>>> End Test Output'
git checkout 32f789fbc5d5a72d9d1ac14935635289eeac9009 -- pandas/tests/groupby/test_min_max.py 2>/dev/null || true
