#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 76d28c7a199bcdb9824b0e3084d846dd65307c44 -- pandas/tests/reshape/merge/test_merge_ordered.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/reshape/merge/test_merge_ordered.py b/pandas/tests/reshape/merge/test_merge_ordered.py
index cfb4e92fb45cd..abd61026b4e37 100644
--- a/pandas/tests/reshape/merge/test_merge_ordered.py
+++ b/pandas/tests/reshape/merge/test_merge_ordered.py
@@ -1,3 +1,5 @@
+import re
+
 import numpy as np
 import pytest
 
@@ -209,3 +211,11 @@ def test_elements_not_in_by_but_in_df(self):
         msg = r"\{'h'\} not found in left columns"
         with pytest.raises(KeyError, match=msg):
             merge_ordered(left, right, on="E", left_by=["G", "h"])
+
+    @pytest.mark.parametrize("invalid_method", ["linear", "carrot"])
+    def test_ffill_validate_fill_method(self, left, right, invalid_method):
+        # GH 55884
+        with pytest.raises(
+            ValueError, match=re.escape("fill_method must be 'ffill' or None")
+        ):
+            merge_ordered(left, right, on="key", fill_method=invalid_method)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_ffill_validate_fill_method[carrot]' 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_ffill_validate_fill_method[linear]' pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_elements_not_in_by_but_in_df 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_empty_sequence_concat[df_seq4-objects.*None]' pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_basic 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_empty_sequence_concat[df_seq0-[Nn]o' 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_empty_sequence_concat[df_seq2-[Nn]o' 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_empty_sequence_concat_ok[arg1]' 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_list_type_by[left0-right0-on0-left_by0-None-expected0]' 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_empty_sequence_concat[df_seq3-objects.*None]' 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_empty_sequence_concat_ok[arg0]' pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_left_by_length_equals_to_right_shape0 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_empty_sequence_concat[df_seq1-[Nn]o' pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_doc_example pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_merge_type pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_multigroup 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_list_type_by[left2-right2-on2-None-right_by2-expected2]' pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_ffill 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_list_type_by[left1-right1-T-left_by1-None-expected1]' 'pandas/tests/reshape/merge/test_merge_ordered.py::TestMergeOrdered::test_empty_sequence_concat_ok[arg2]'
: '>>>>> End Test Output'
git checkout 76d28c7a199bcdb9824b0e3084d846dd65307c44 -- pandas/tests/reshape/merge/test_merge_ordered.py 2>/dev/null || true
