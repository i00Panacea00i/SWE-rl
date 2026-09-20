#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 3b56e7f17640665695ba413a023b67268c2b5bb4 -- tests/test_generalized_dice_loss.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_generalized_dice_loss.py b/tests/test_generalized_dice_loss.py
--- a/tests/test_generalized_dice_loss.py
+++ b/tests/test_generalized_dice_loss.py
@@ -48,7 +48,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        0.435035,
+        0.469964,
     ],
     [  # shape: (2, 2, 3), (2, 1, 3)
         {"include_background": True, "to_onehot_y": True, "softmax": True, "smooth_nr": 1e-4, "smooth_dr": 1e-4},
@@ -56,7 +56,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        0.3837,
+        0.414507,
     ],
     [  # shape: (2, 2, 3), (2, 1, 3)
         {
@@ -71,7 +71,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        1.5348,
+        0.829015,
     ],
     [  # shape: (2, 2, 3), (2, 1, 3)
         {
@@ -86,7 +86,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        [[[0.210949], [0.295351]], [[0.599976], [0.428522]]],
+        [[[0.273476]], [[0.555539]]],
     ],
     [  # shape: (2, 2, 3), (2, 1, 3)
         {"include_background": False, "to_onehot_y": True, "smooth_nr": 1e-8, "smooth_dr": 1e-8},
@@ -114,7 +114,7 @@
             "input": torch.tensor([[[0.0, 10.0, 10.0, 10.0], [10.0, 0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1, 1, 0, 0]]]),
         },
-        0.26669,
+        0.250023,
     ],
     [  # shape: (2, 1, 2, 2), (2, 1, 2, 2)
         {"include_background": True, "other_act": torch.tanh, "smooth_nr": 1e-4, "smooth_dr": 1e-4},
@@ -136,7 +136,7 @@
             "input": torch.tensor([[[-1.0, 0.0, 1.0], [1.0, 0.0, -1.0]], [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]]),
             "target": torch.tensor([[[1.0, 0.0, 0.0]], [[1.0, 1.0, 0.0]]]),
         },
-        -8.55485,
+        -0.097833,
     ],
 ]
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_04 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_05 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_06 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_11 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_03 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_09 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_batch tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_differentiability tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_input_warnings tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_00 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_ill_shape tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_08 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_script tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_02 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_07 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_10 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_01 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_ill_opts
: '>>>>> End Test Output'
git checkout 3b56e7f17640665695ba413a023b67268c2b5bb4 -- tests/test_generalized_dice_loss.py 2>/dev/null || true
