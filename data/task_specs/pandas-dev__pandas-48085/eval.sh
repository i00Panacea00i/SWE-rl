#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 3a3ed661c0a62b97f6fffc05bbf1fe6769b908cc -- pandas/tests/frame/methods/test_add_prefix_suffix.py pandas/tests/series/methods/test_add_prefix_suffix.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/frame/methods/test_add_prefix_suffix.py b/pandas/tests/frame/methods/test_add_prefix_suffix.py
index ea75e9ff51552..92d7cdd7990e1 100644
--- a/pandas/tests/frame/methods/test_add_prefix_suffix.py
+++ b/pandas/tests/frame/methods/test_add_prefix_suffix.py
@@ -1,3 +1,5 @@
+import pytest
+
 from pandas import Index
 import pandas._testing as tm
 
@@ -18,3 +20,30 @@ def test_add_prefix_suffix(float_frame):
     with_pct_suffix = float_frame.add_suffix("%")
     expected = Index([f"{c}%" for c in float_frame.columns])
     tm.assert_index_equal(with_pct_suffix.columns, expected)
+
+
+def test_add_prefix_suffix_axis(float_frame):
+    # GH 47819
+    with_prefix = float_frame.add_prefix("foo#", axis=0)
+    expected = Index([f"foo#{c}" for c in float_frame.index])
+    tm.assert_index_equal(with_prefix.index, expected)
+
+    with_prefix = float_frame.add_prefix("foo#", axis=1)
+    expected = Index([f"foo#{c}" for c in float_frame.columns])
+    tm.assert_index_equal(with_prefix.columns, expected)
+
+    with_pct_suffix = float_frame.add_suffix("#foo", axis=0)
+    expected = Index([f"{c}#foo" for c in float_frame.index])
+    tm.assert_index_equal(with_pct_suffix.index, expected)
+
+    with_pct_suffix = float_frame.add_suffix("#foo", axis=1)
+    expected = Index([f"{c}#foo" for c in float_frame.columns])
+    tm.assert_index_equal(with_pct_suffix.columns, expected)
+
+
+def test_add_prefix_suffix_invalid_axis(float_frame):
+    with pytest.raises(ValueError, match="No axis named 2 for object type DataFrame"):
+        float_frame.add_prefix("foo#", axis=2)
+
+    with pytest.raises(ValueError, match="No axis named 2 for object type DataFrame"):
+        float_frame.add_suffix("foo#", axis=2)
diff --git a/pandas/tests/series/methods/test_add_prefix_suffix.py b/pandas/tests/series/methods/test_add_prefix_suffix.py
new file mode 100644
index 0000000000000..289a56b98b7e1
--- /dev/null
+++ b/pandas/tests/series/methods/test_add_prefix_suffix.py
@@ -0,0 +1,41 @@
+import pytest
+
+from pandas import Index
+import pandas._testing as tm
+
+
+def test_add_prefix_suffix(string_series):
+    with_prefix = string_series.add_prefix("foo#")
+    expected = Index([f"foo#{c}" for c in string_series.index])
+    tm.assert_index_equal(with_prefix.index, expected)
+
+    with_suffix = string_series.add_suffix("#foo")
+    expected = Index([f"{c}#foo" for c in string_series.index])
+    tm.assert_index_equal(with_suffix.index, expected)
+
+    with_pct_prefix = string_series.add_prefix("%")
+    expected = Index([f"%{c}" for c in string_series.index])
+    tm.assert_index_equal(with_pct_prefix.index, expected)
+
+    with_pct_suffix = string_series.add_suffix("%")
+    expected = Index([f"{c}%" for c in string_series.index])
+    tm.assert_index_equal(with_pct_suffix.index, expected)
+
+
+def test_add_prefix_suffix_axis(string_series):
+    # GH 47819
+    with_prefix = string_series.add_prefix("foo#", axis=0)
+    expected = Index([f"foo#{c}" for c in string_series.index])
+    tm.assert_index_equal(with_prefix.index, expected)
+
+    with_pct_suffix = string_series.add_suffix("#foo", axis=0)
+    expected = Index([f"{c}#foo" for c in string_series.index])
+    tm.assert_index_equal(with_pct_suffix.index, expected)
+
+
+def test_add_prefix_suffix_invalid_axis(string_series):
+    with pytest.raises(ValueError, match="No axis named 1 for object type Series"):
+        string_series.add_prefix("foo#", axis=1)
+
+    with pytest.raises(ValueError, match="No axis named 1 for object type Series"):
+        string_series.add_suffix("foo#", axis=1)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail pandas/tests/frame/methods/test_add_prefix_suffix.py::test_add_prefix_suffix_axis pandas/tests/series/methods/test_add_prefix_suffix.py::test_add_prefix_suffix_axis pandas/tests/frame/methods/test_add_prefix_suffix.py::test_add_prefix_suffix_invalid_axis pandas/tests/series/methods/test_add_prefix_suffix.py::test_add_prefix_suffix_invalid_axis pandas/tests/frame/methods/test_add_prefix_suffix.py::test_add_prefix_suffix pandas/tests/series/methods/test_add_prefix_suffix.py::test_add_prefix_suffix
: '>>>>> End Test Output'
git checkout 3a3ed661c0a62b97f6fffc05bbf1fe6769b908cc -- pandas/tests/frame/methods/test_add_prefix_suffix.py pandas/tests/series/methods/test_add_prefix_suffix.py 2>/dev/null || true
