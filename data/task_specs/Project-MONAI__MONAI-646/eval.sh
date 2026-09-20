#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout db9dfdaf08c737570b66254f3786eff7eec5b45b -- tests/test_dice_loss.py tests/test_masked_dice_loss.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_dice_loss.py b/tests/test_dice_loss.py
--- a/tests/test_dice_loss.py
+++ b/tests/test_dice_loss.py
@@ -106,7 +106,7 @@
             "target": torch.tensor([[[[1.0, 0.0], [1.0, 1.0]]]]),
             "smooth": 1e-5,
         },
-        -0.059094,
+        0.470451,
     ],
 ]
 
diff --git a/tests/test_masked_dice_loss.py b/tests/test_masked_dice_loss.py
--- a/tests/test_masked_dice_loss.py
+++ b/tests/test_masked_dice_loss.py
@@ -110,7 +110,7 @@
             "target": torch.tensor([[[[1.0, 0.0], [1.0, 1.0]]]]),
             "smooth": 1e-5,
         },
-        -0.059094,
+        0.470451,
     ],
 ]
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_dice_loss.py::TestDiceLoss::test_shape_9 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_9 tests/test_dice_loss.py::TestDiceLoss::test_shape_7 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_4 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_2 tests/test_dice_loss.py::TestDiceLoss::test_shape_1 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_6 tests/test_dice_loss.py::TestDiceLoss::test_input_warnings tests/test_dice_loss.py::TestDiceLoss::test_ill_shape tests/test_dice_loss.py::TestDiceLoss::test_shape_0 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_3 tests/test_dice_loss.py::TestDiceLoss::test_shape_5 tests/test_masked_dice_loss.py::TestDiceLoss::test_ill_shape tests/test_dice_loss.py::TestDiceLoss::test_shape_2 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_7 tests/test_dice_loss.py::TestDiceLoss::test_shape_3 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_5 tests/test_dice_loss.py::TestDiceLoss::test_shape_8 tests/test_dice_loss.py::TestDiceLoss::test_ill_opts tests/test_masked_dice_loss.py::TestDiceLoss::test_ill_opts tests/test_masked_dice_loss.py::TestDiceLoss::test_input_warnings tests/test_dice_loss.py::TestDiceLoss::test_shape_4 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_8 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_1 tests/test_dice_loss.py::TestDiceLoss::test_shape_6 tests/test_masked_dice_loss.py::TestDiceLoss::test_shape_0
: '>>>>> End Test Output'
git checkout db9dfdaf08c737570b66254f3786eff7eec5b45b -- tests/test_dice_loss.py tests/test_masked_dice_loss.py 2>/dev/null || true
