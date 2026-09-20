#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout c38d503a587f1779914bd071a1b2d66a6d9080c2 -- tests/test_generalized_dice_loss.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_generalized_dice_loss.py b/tests/test_generalized_dice_loss.py
--- a/tests/test_generalized_dice_loss.py
+++ b/tests/test_generalized_dice_loss.py
@@ -46,7 +46,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        0.469964,
+        0.435035,
     ],
     [  # shape: (2, 2, 3), (2, 1, 3)
         {"include_background": True, "to_onehot_y": True, "softmax": True, "smooth_nr": 1e-4, "smooth_dr": 1e-4},
@@ -54,7 +54,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        0.414507,
+        0.3837,
     ],
     [  # shape: (2, 2, 3), (2, 1, 3)
         {
@@ -69,7 +69,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        0.829015,
+        1.5348,
     ],
     [  # shape: (2, 2, 3), (2, 1, 3)
         {
@@ -84,7 +84,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        [[[0.273476]], [[0.555539]]],
+        [[[0.210949], [0.295351]], [[0.599976], [0.428522]]],
     ],
     [  # shape: (2, 2, 3), (2, 1, 3)
         {"include_background": False, "to_onehot_y": True, "smooth_nr": 1e-8, "smooth_dr": 1e-8},
@@ -112,7 +112,7 @@
             "input": torch.tensor([[[0.0, 10.0, 10.0, 10.0], [10.0, 0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1, 1, 0, 0]]]),
         },
-        0.250023,
+        0.26669,
     ],
     [  # shape: (2, 1, 2, 2), (2, 1, 2, 2)
         {"include_background": True, "other_act": torch.tanh, "smooth_nr": 1e-4, "smooth_dr": 1e-4},
@@ -134,7 +134,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        -0.097833,
+        -8.55485,
     ],
 ]
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_04 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_05 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_06 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_11 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_03 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_09 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_batch tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_differentiability tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_input_warnings tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_00 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_ill_shape tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_08 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_script tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_02 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_07 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_10 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_01 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_ill_opts
: '>>>>> End Test Output'
git checkout c38d503a587f1779914bd071a1b2d66a6d9080c2 -- tests/test_generalized_dice_loss.py 2>/dev/null || true
