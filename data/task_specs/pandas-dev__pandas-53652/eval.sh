#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout d2d830d6366ea9569b830c5214dfcd16d61bd8a3 -- pandas/tests/indexing/test_datetime.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/indexing/test_datetime.py b/pandas/tests/indexing/test_datetime.py
index 15e1fae77d65b..6510612ba6f87 100644
--- a/pandas/tests/indexing/test_datetime.py
+++ b/pandas/tests/indexing/test_datetime.py
@@ -168,3 +168,21 @@ def test_getitem_str_slice_millisecond_resolution(self, frame_or_series):
             ],
         )
         tm.assert_equal(result, expected)
+
+    def test_getitem_pyarrow_index(self, frame_or_series):
+        # GH 53644
+        pytest.importorskip("pyarrow")
+        obj = frame_or_series(
+            range(5),
+            index=date_range("2020", freq="D", periods=5).astype(
+                "timestamp[us][pyarrow]"
+            ),
+        )
+        result = obj.loc[obj.index[:-3]]
+        expected = frame_or_series(
+            range(2),
+            index=date_range("2020", freq="D", periods=2).astype(
+                "timestamp[us][pyarrow]"
+            ),
+        )
+        tm.assert_equal(result, expected)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_getitem_pyarrow_index[DataFrame]' 'pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_getitem_pyarrow_index[Series]' 'pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_getitem_str_slice_millisecond_resolution[DataFrame]' pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_indexing_with_datetime_tz pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_indexing_fast_xs 'pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_getitem_str_slice_millisecond_resolution[Series]' pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_nanosecond_getitem_setitem_with_tz 'pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_indexing_with_datetimeindex_tz[loc]' pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_consistency_with_tz_aware_scalar 'pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_indexing_with_datetimeindex_tz[setitem]' pandas/tests/indexing/test_datetime.py::TestDatetimeIndex::test_get_loc_naive_dti_aware_str_deprecated
: '>>>>> End Test Output'
git checkout d2d830d6366ea9569b830c5214dfcd16d61bd8a3 -- pandas/tests/indexing/test_datetime.py 2>/dev/null || true
