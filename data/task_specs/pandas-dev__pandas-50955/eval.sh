#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 450a1f04b7707ceb983a331768933861c09b3223 -- pandas/tests/frame/methods/test_value_counts.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/frame/methods/test_value_counts.py b/pandas/tests/frame/methods/test_value_counts.py
index e8c129fd12bfd..355f05cd5156c 100644
--- a/pandas/tests/frame/methods/test_value_counts.py
+++ b/pandas/tests/frame/methods/test_value_counts.py
@@ -1,4 +1,5 @@
 import numpy as np
+import pytest
 
 import pandas as pd
 import pandas._testing as tm
@@ -155,3 +156,22 @@ def test_data_frame_value_counts_dropna_false(nulls_fixture):
     )
 
     tm.assert_series_equal(result, expected)
+
+
+@pytest.mark.parametrize("columns", (["first_name", "middle_name"], [0, 1]))
+def test_data_frame_value_counts_subset(nulls_fixture, columns):
+    # GH 50829
+    df = pd.DataFrame(
+        {
+            columns[0]: ["John", "Anne", "John", "Beth"],
+            columns[1]: ["Smith", nulls_fixture, nulls_fixture, "Louise"],
+        },
+    )
+    result = df.value_counts(columns[0])
+    expected = pd.Series(
+        data=[2, 1, 1],
+        index=pd.Index(["John", "Anne", "Beth"], name=columns[0]),
+        name="count",
+    )
+
+    tm.assert_series_equal(result, expected)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[float1-columns1]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[NaTType-columns1]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[Decimal-columns1]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[NoneType-columns1]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[float0-columns1]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[NAType-columns1]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[NAType-columns0]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_true[float1]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_true[float0]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_true[NAType]' pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_unsorted 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_false[NAType]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[float1-columns0]' pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_default 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_true[NoneType]' pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_empty 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_false[float1]' pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_empty_normalize 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_false[NoneType]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[NaTType-columns0]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[Decimal-columns0]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_true[NaTType]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_false[Decimal]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_false[NaTType]' pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_ascending 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_false[float0]' pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_single_col_default 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[float0-columns0]' pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_normalize 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_subset[NoneType-columns0]' 'pandas/tests/frame/methods/test_value_counts.py::test_data_frame_value_counts_dropna_true[Decimal]'
: '>>>>> End Test Output'
git checkout 450a1f04b7707ceb983a331768933861c09b3223 -- pandas/tests/frame/methods/test_value_counts.py 2>/dev/null || true
