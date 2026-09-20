#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 192a4e3e5964dcf991db5225bfc4a468e6ea90ed -- pandas/tests/indexes/test_datetimelike.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/indexes/test_datetimelike.py b/pandas/tests/indexes/test_datetimelike.py
index 71cc7f29c62bc..5ad2e9b2f717e 100644
--- a/pandas/tests/indexes/test_datetimelike.py
+++ b/pandas/tests/indexes/test_datetimelike.py
@@ -159,3 +159,11 @@ def test_where_cast_str(self, simple_index):
 
         result = index.where(mask, ["foo"])
         tm.assert_index_equal(result, expected)
+
+    @pytest.mark.parametrize("unit", ["ns", "us", "ms", "s"])
+    def test_diff(self, unit):
+        # GH 55080
+        dti = pd.to_datetime([10, 20, 30], unit=unit).as_unit(unit)
+        result = dti.diff(1)
+        expected = pd.TimedeltaIndex([pd.NaT, 10, 10], unit=unit).as_unit(unit)
+        tm.assert_index_equal(result, expected)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_diff[ns]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_diff[ms]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_diff[us]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_diff[s]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_getitem_preserves_freq[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_view[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_dictlike[simple_index1-<lambda>1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_where_cast_str[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_can_hold_identifiers[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_dictlike[simple_index0-<lambda>0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_shift_identity[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_shift_identity[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_str[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_dictlike[simple_index2-<lambda>1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_isin[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_callable[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_shift_empty[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_dictlike[simple_index1-<lambda>0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_can_hold_identifiers[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_where_cast_str[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_argsort_matches_array[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_getitem_preserves_freq[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_shift_empty[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_shift_empty[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_view[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_str[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_can_hold_identifiers[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_callable[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_getitem_preserves_freq[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_where_cast_str[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_callable[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_str[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_argsort_matches_array[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_dictlike[simple_index0-<lambda>1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_shift_identity[simple_index0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_map_dictlike[simple_index2-<lambda>0]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_isin[simple_index1]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_argsort_matches_array[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_view[simple_index2]' 'pandas/tests/indexes/test_datetimelike.py::TestDatetimeLike::test_isin[simple_index0]'
: '>>>>> End Test Output'
git checkout 192a4e3e5964dcf991db5225bfc4a468e6ea90ed -- pandas/tests/indexes/test_datetimelike.py 2>/dev/null || true
