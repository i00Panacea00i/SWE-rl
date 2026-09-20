#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8f869f3de0048d01fcf2f8198644fca72b926aa9 -- pandas/tests/indexes/multi/test_join.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/indexes/multi/test_join.py b/pandas/tests/indexes/multi/test_join.py
index 23d5325dde2bb..aa2f2ca5af7bd 100644
--- a/pandas/tests/indexes/multi/test_join.py
+++ b/pandas/tests/indexes/multi/test_join.py
@@ -6,6 +6,8 @@
     Index,
     Interval,
     MultiIndex,
+    Series,
+    StringDtype,
 )
 import pandas._testing as tm
 
@@ -161,6 +163,52 @@ def test_join_overlapping_interval_level():
     tm.assert_index_equal(result, expected)
 
 
+def test_join_midx_ea():
+    # GH#49277
+    midx = MultiIndex.from_arrays(
+        [Series([1, 1, 3], dtype="Int64"), Series([1, 2, 3], dtype="Int64")],
+        names=["a", "b"],
+    )
+    midx2 = MultiIndex.from_arrays(
+        [Series([1], dtype="Int64"), Series([3], dtype="Int64")], names=["a", "c"]
+    )
+    result = midx.join(midx2, how="inner")
+    expected = MultiIndex.from_arrays(
+        [
+            Series([1, 1], dtype="Int64"),
+            Series([1, 2], dtype="Int64"),
+            Series([3, 3], dtype="Int64"),
+        ],
+        names=["a", "b", "c"],
+    )
+    tm.assert_index_equal(result, expected)
+
+
+def test_join_midx_string():
+    # GH#49277
+    midx = MultiIndex.from_arrays(
+        [
+            Series(["a", "a", "c"], dtype=StringDtype()),
+            Series(["a", "b", "c"], dtype=StringDtype()),
+        ],
+        names=["a", "b"],
+    )
+    midx2 = MultiIndex.from_arrays(
+        [Series(["a"], dtype=StringDtype()), Series(["c"], dtype=StringDtype())],
+        names=["a", "c"],
+    )
+    result = midx.join(midx2, how="inner")
+    expected = MultiIndex.from_arrays(
+        [
+            Series(["a", "a"], dtype=StringDtype()),
+            Series(["a", "b"], dtype=StringDtype()),
+            Series(["c", "c"], dtype=StringDtype()),
+        ],
+        names=["a", "b", "c"],
+    )
+    tm.assert_index_equal(result, expected)
+
+
 def test_join_multi_with_nan():
     # GH29252
     df1 = DataFrame(

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail pandas/tests/indexes/multi/test_join.py::test_join_midx_ea pandas/tests/indexes/multi/test_join.py::test_join_midx_string 'pandas/tests/indexes/multi/test_join.py::test_join_self[inner]' pandas/tests/indexes/multi/test_join.py::test_join_level_corner_case 'pandas/tests/indexes/multi/test_join.py::test_join_level[outer-other1]' 'pandas/tests/indexes/multi/test_join.py::test_join_level[right-other0]' pandas/tests/indexes/multi/test_join.py::test_join_multi_wrong_order 'pandas/tests/indexes/multi/test_join.py::test_join_level[left-other2]' 'pandas/tests/indexes/multi/test_join.py::test_join_level[outer-other2]' pandas/tests/indexes/multi/test_join.py::test_join_multi_with_nan 'pandas/tests/indexes/multi/test_join.py::test_join_self_unique[outer]' 'pandas/tests/indexes/multi/test_join.py::test_join_level[inner-other2]' 'pandas/tests/indexes/multi/test_join.py::test_join_self_unique[inner]' 'pandas/tests/indexes/multi/test_join.py::test_join_self[left]' 'pandas/tests/indexes/multi/test_join.py::test_join_self[outer]' 'pandas/tests/indexes/multi/test_join.py::test_join_level[right-other2]' pandas/tests/indexes/multi/test_join.py::test_join_multi 'pandas/tests/indexes/multi/test_join.py::test_join_level[right-other1]' 'pandas/tests/indexes/multi/test_join.py::test_join_level[left-other1]' 'pandas/tests/indexes/multi/test_join.py::test_join_self_unique[left]' pandas/tests/indexes/multi/test_join.py::test_join_multi_return_indexers 'pandas/tests/indexes/multi/test_join.py::test_join_self[right]' 'pandas/tests/indexes/multi/test_join.py::test_join_level[inner-other1]' pandas/tests/indexes/multi/test_join.py::test_join_overlapping_interval_level 'pandas/tests/indexes/multi/test_join.py::test_join_level[left-other0]' 'pandas/tests/indexes/multi/test_join.py::test_join_level[outer-other0]' 'pandas/tests/indexes/multi/test_join.py::test_join_level[inner-other0]' 'pandas/tests/indexes/multi/test_join.py::test_join_self_unique[right]'
: '>>>>> End Test Output'
git checkout 8f869f3de0048d01fcf2f8198644fca72b926aa9 -- pandas/tests/indexes/multi/test_join.py 2>/dev/null || true
