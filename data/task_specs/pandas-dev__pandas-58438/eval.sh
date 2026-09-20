#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout a052307e2deb36a3548b58de8888765fb4b7bed0 -- pandas/tests/series/accessors/test_list_accessor.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/series/accessors/test_list_accessor.py b/pandas/tests/series/accessors/test_list_accessor.py
index 1c60567c1a530..c153e800cb534 100644
--- a/pandas/tests/series/accessors/test_list_accessor.py
+++ b/pandas/tests/series/accessors/test_list_accessor.py
@@ -31,10 +31,23 @@ def test_list_getitem(list_dtype):
     tm.assert_series_equal(actual, expected)
 
 
+def test_list_getitem_index():
+    # GH 58425
+    ser = Series(
+        [[1, 2, 3], [4, None, 5], None],
+        dtype=ArrowDtype(pa.list_(pa.int64())),
+        index=[1, 3, 7],
+    )
+    actual = ser.list[1]
+    expected = Series([2, None, None], dtype="int64[pyarrow]", index=[1, 3, 7])
+    tm.assert_series_equal(actual, expected)
+
+
 def test_list_getitem_slice():
     ser = Series(
         [[1, 2, 3], [4, None, 5], None],
         dtype=ArrowDtype(pa.list_(pa.int64())),
+        index=[1, 3, 7],
     )
     if pa_version_under11p0:
         with pytest.raises(
@@ -44,7 +57,9 @@ def test_list_getitem_slice():
     else:
         actual = ser.list[1:None:None]
         expected = Series(
-            [[2, 3], [None, 5], None], dtype=ArrowDtype(pa.list_(pa.int64()))
+            [[2, 3], [None, 5], None],
+            dtype=ArrowDtype(pa.list_(pa.int64())),
+            index=[1, 3, 7],
         )
         tm.assert_series_equal(actual, expected)
 
@@ -61,11 +76,15 @@ def test_list_len():
 
 def test_list_flatten():
     ser = Series(
-        [[1, 2, 3], [4, None], None],
+        [[1, 2, 3], None, [4, None], [], [7, 8]],
         dtype=ArrowDtype(pa.list_(pa.int64())),
     )
     actual = ser.list.flatten()
-    expected = Series([1, 2, 3, 4, None], dtype=ArrowDtype(pa.int64()))
+    expected = Series(
+        [1, 2, 3, 4, None, 7, 8],
+        dtype=ArrowDtype(pa.int64()),
+        index=[0, 0, 0, 2, 2, 4, 4],
+    )
     tm.assert_series_equal(actual, expected)
 
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem_slice pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem_index pandas/tests/series/accessors/test_list_accessor.py::test_list_flatten pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem_slice_invalid pandas/tests/series/accessors/test_list_accessor.py::test_list_accessor_not_iterable pandas/tests/series/accessors/test_list_accessor.py::test_list_accessor_non_list_dtype 'pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem[list_dtype0]' 'pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem[list_dtype1]' 'pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem_invalid_index[list_dtype2]' 'pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem[list_dtype2]' 'pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem_invalid_index[list_dtype0]' pandas/tests/series/accessors/test_list_accessor.py::test_list_len 'pandas/tests/series/accessors/test_list_accessor.py::test_list_getitem_invalid_index[list_dtype1]'
: '>>>>> End Test Output'
git checkout a052307e2deb36a3548b58de8888765fb4b7bed0 -- pandas/tests/series/accessors/test_list_accessor.py 2>/dev/null || true
