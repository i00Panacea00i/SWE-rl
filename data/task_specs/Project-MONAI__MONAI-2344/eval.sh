#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 6476cee7c16cce81278c4555f5f25ecd02181d31 -- tests/test_upsample_block.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_upsample_block.py b/tests/test_upsample_block.py
--- a/tests/test_upsample_block.py
+++ b/tests/test_upsample_block.py
@@ -35,6 +35,16 @@
         (16, 4, 32, 24, 48),
         (16, 4, 64, 48, 96),
     ],  # 4-channel 3D, batch 16
+    [
+        {"dimensions": 3, "in_channels": 4, "mode": "nontrainable", "size": 64},
+        (16, 4, 32, 24, 48),
+        (16, 4, 64, 64, 64),
+    ],  # 4-channel 3D, batch 16
+    [
+        {"dimensions": 3, "in_channels": 4, "mode": "nontrainable", "size": (64, 24, 48)},
+        (16, 4, 32, 24, 48),
+        (16, 4, 64, 24, 48),
+    ],  # 4-channel 3D, batch 16
     [
         {"dimensions": 3, "in_channels": 1, "mode": "deconv", "scale_factor": 3, "align_corners": False},
         (16, 1, 10, 15, 20),

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_upsample_block.py::TestUpsample::test_shape_04 tests/test_upsample_block.py::TestUpsample::test_shape_05 tests/test_upsample_block.py::TestUpsample::test_shape_15 tests/test_upsample_block.py::TestUpsample::test_shape_03 tests/test_upsample_block.py::TestUpsample::test_shape_18 tests/test_upsample_block.py::TestUpsample::test_shape_02 tests/test_upsample_block.py::TestUpsample::test_shape_06 tests/test_upsample_block.py::TestUpsample::test_shape_13 tests/test_upsample_block.py::TestUpsample::test_shape_07 tests/test_upsample_block.py::TestUpsample::test_shape_21 tests/test_upsample_block.py::TestUpsample::test_shape_19 tests/test_upsample_block.py::TestUpsample::test_shape_09 tests/test_upsample_block.py::TestUpsample::test_shape_12 tests/test_upsample_block.py::TestUpsample::test_shape_17 tests/test_upsample_block.py::TestUpsample::test_shape_11 tests/test_upsample_block.py::TestUpsample::test_shape_14 tests/test_upsample_block.py::TestUpsample::test_shape_08 tests/test_upsample_block.py::TestUpsample::test_shape_01 tests/test_upsample_block.py::TestUpsample::test_shape_00 tests/test_upsample_block.py::TestUpsample::test_shape_10 tests/test_upsample_block.py::TestUpsample::test_shape_20 tests/test_upsample_block.py::TestUpsample::test_shape_16
: '>>>>> End Test Output'
git checkout 6476cee7c16cce81278c4555f5f25ecd02181d31 -- tests/test_upsample_block.py 2>/dev/null || true
