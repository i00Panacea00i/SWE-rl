#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout acd2f5f889df788be7c308bff7db282d71c80b3a -- pandas/tests/frame/methods/test_isetitem.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/frame/methods/test_isetitem.py b/pandas/tests/frame/methods/test_isetitem.py
new file mode 100644
index 0000000000000..59328aafefefb
--- /dev/null
+++ b/pandas/tests/frame/methods/test_isetitem.py
@@ -0,0 +1,37 @@
+from pandas import (
+    DataFrame,
+    Series,
+)
+import pandas._testing as tm
+
+
+class TestDataFrameSetItem:
+    def test_isetitem_ea_df(self):
+        # GH#49922
+        df = DataFrame([[1, 2, 3], [4, 5, 6]])
+        rhs = DataFrame([[11, 12], [13, 14]], dtype="Int64")
+
+        df.isetitem([0, 1], rhs)
+        expected = DataFrame(
+            {
+                0: Series([11, 13], dtype="Int64"),
+                1: Series([12, 14], dtype="Int64"),
+                2: [3, 6],
+            }
+        )
+        tm.assert_frame_equal(df, expected)
+
+    def test_isetitem_ea_df_scalar_indexer(self):
+        # GH#49922
+        df = DataFrame([[1, 2, 3], [4, 5, 6]])
+        rhs = DataFrame([[11], [13]], dtype="Int64")
+
+        df.isetitem(2, rhs)
+        expected = DataFrame(
+            {
+                0: [1, 4],
+                1: [2, 5],
+                2: Series([11, 13], dtype="Int64"),
+            }
+        )
+        tm.assert_frame_equal(df, expected)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail pandas/tests/frame/methods/test_isetitem.py::TestDataFrameSetItem::test_isetitem_ea_df pandas/tests/frame/methods/test_isetitem.py::TestDataFrameSetItem::test_isetitem_ea_df_scalar_indexer
: '>>>>> End Test Output'
git checkout acd2f5f889df788be7c308bff7db282d71c80b3a -- pandas/tests/frame/methods/test_isetitem.py 2>/dev/null || true
