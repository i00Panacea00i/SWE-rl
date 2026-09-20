#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout d83fa5660e87d99f9ddcfcfb4695cbdf53a3884c -- tests/test_resnet.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_resnet.py b/tests/test_resnet.py
--- a/tests/test_resnet.py
+++ b/tests/test_resnet.py
@@ -107,6 +107,7 @@
         "num_classes": 3,
         "conv1_t_size": [3],
         "conv1_t_stride": 1,
+        "act": ("relu", {"inplace": False}),
     },
     (1, 2, 32),
     (1, 3),
@@ -185,13 +186,29 @@
     (1, 3),
 ]
 
+TEST_CASE_8 = [
+    {
+        "block": "bottleneck",
+        "layers": [3, 4, 6, 3],
+        "block_inplanes": [64, 128, 256, 512],
+        "spatial_dims": 1,
+        "n_input_channels": 2,
+        "num_classes": 3,
+        "conv1_t_size": [3],
+        "conv1_t_stride": 1,
+        "act": ("relu", {"inplace": False}),
+    },
+    (1, 2, 32),
+    (1, 3),
+]
+
 TEST_CASES = []
 PRETRAINED_TEST_CASES = []
 for case in [TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_2_A, TEST_CASE_3_A]:
     for model in [resnet10, resnet18, resnet34, resnet50, resnet101, resnet152, resnet200]:
         TEST_CASES.append([model, *case])
         PRETRAINED_TEST_CASES.append([model, *case])
-for case in [TEST_CASE_5, TEST_CASE_5_A, TEST_CASE_6, TEST_CASE_7]:
+for case in [TEST_CASE_5, TEST_CASE_5_A, TEST_CASE_6, TEST_CASE_7, TEST_CASE_8]:
     TEST_CASES.append([ResNet, *case])
 
 TEST_SCRIPT_CASES = [

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_resnet.py::TestResNet::test_resnet_shape_18 tests/test_resnet.py::TestResNet::test_resnet_shape_16 tests/test_resnet.py::TestResNet::test_resnet_shape_15 tests/test_resnet.py::TestResNet::test_resnet_shape_20 tests/test_resnet.py::TestResNet::test_resnet_shape_19 tests/test_resnet.py::TestResNet::test_resnet_shape_14 tests/test_resnet.py::TestResNet::test_resnet_shape_17 tests/test_resnet.py::TestResNet::test_resnet_shape_39 tests/test_resnet.py::TestResNet::test_resnet_shape_32 tests/test_resnet.py::TestResNet::test_resnet_shape_29 tests/test_resnet.py::TestResNet::test_resnet_shape_35 tests/test_resnet.py::TestResNet::test_resnet_shape_33 tests/test_resnet.py::TestResNet::test_resnet_shape_38 tests/test_resnet.py::TestResNet::test_script_2 tests/test_resnet.py::TestResNet::test_resnet_shape_03 tests/test_resnet.py::TestResNet::test_resnet_shape_22 tests/test_resnet.py::TestResNet::test_resnet_shape_10 tests/test_resnet.py::TestResNet::test_resnet_shape_34 tests/test_resnet.py::TestResNet::test_resnet_shape_23 tests/test_resnet.py::TestResNet::test_resnet_shape_27 tests/test_resnet.py::TestResNet::test_script_5 tests/test_resnet.py::TestResNet::test_resnet_shape_28 tests/test_resnet.py::TestResNet::test_resnet_shape_36 tests/test_resnet.py::TestResNet::test_resnet_shape_31 tests/test_resnet.py::TestResNet::test_resnet_shape_11 tests/test_resnet.py::TestResNet::test_script_0 tests/test_resnet.py::TestResNet::test_resnet_shape_08 tests/test_resnet.py::TestResNet::test_resnet_shape_00 tests/test_resnet.py::TestResNet::test_script_1 tests/test_resnet.py::TestResNet::test_resnet_shape_24 tests/test_resnet.py::TestResNet::test_script_3 tests/test_resnet.py::TestResNet::test_resnet_shape_06 tests/test_resnet.py::TestResNet::test_resnet_shape_26 tests/test_resnet.py::TestResNet::test_script_4 tests/test_resnet.py::TestResNet::test_resnet_shape_12 tests/test_resnet.py::TestResNet::test_resnet_shape_04 tests/test_resnet.py::TestResNet::test_resnet_shape_30 tests/test_resnet.py::TestResNet::test_resnet_shape_07 tests/test_resnet.py::TestResNet::test_resnet_shape_25 tests/test_resnet.py::TestResNet::test_resnet_shape_01 tests/test_resnet.py::TestResNet::test_resnet_shape_21 tests/test_resnet.py::TestResNet::test_resnet_shape_05 tests/test_resnet.py::TestResNet::test_resnet_shape_09 tests/test_resnet.py::TestResNet::test_resnet_shape_13 tests/test_resnet.py::TestResNet::test_resnet_shape_37 tests/test_resnet.py::TestResNet::test_resnet_shape_02 tests/test_resnet.py::TestResNet::test_script_6
: '>>>>> End Test Output'
git checkout d83fa5660e87d99f9ddcfcfb4695cbdf53a3884c -- tests/test_resnet.py 2>/dev/null || true
