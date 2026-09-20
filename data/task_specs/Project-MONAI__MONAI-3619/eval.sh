#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 3907cb4b6ba79887a649ffc17f45ed9bebcd0431 -- tests/test_generalized_dice_loss.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_generalized_dice_loss.py b/tests/test_generalized_dice_loss.py
--- a/tests/test_generalized_dice_loss.py
+++ b/tests/test_generalized_dice_loss.py
@@ -173,6 +173,26 @@ def test_input_warnings(self):
             loss = GeneralizedDiceLoss(to_onehot_y=True)
             loss.forward(chn_input, chn_target)
 
+    def test_differentiability(self):
+        prediction = torch.ones((1, 1, 1, 3))
+        target = torch.ones((1, 1, 1, 3))
+        prediction.requires_grad = True
+        target.requires_grad = True
+
+        generalized_dice_loss = GeneralizedDiceLoss()
+        loss = generalized_dice_loss(prediction, target)
+        self.assertNotEqual(loss.grad_fn, None)
+
+    def test_batch(self):
+        prediction = torch.zeros(2, 3, 3, 3)
+        target = torch.zeros(2, 3, 3, 3)
+        prediction.requires_grad = True
+        target.requires_grad = True
+
+        generalized_dice_loss = GeneralizedDiceLoss(batch=True)
+        loss = generalized_dice_loss(prediction, target)
+        self.assertNotEqual(loss.grad_fn, None)
+
     @SkipIfBeforePyTorchVersion((1, 7, 0))
     def test_script(self):
         loss = GeneralizedDiceLoss()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_batch tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_differentiability tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_ill_opts tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_04 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_input_warnings tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_00 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_ill_shape tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_05 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_08 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_script tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_02 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_06 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_07 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_10 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_01 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_11 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_03 tests/test_generalized_dice_loss.py::TestGeneralizedDiceLoss::test_shape_09
: '>>>>> End Test Output'
git checkout 3907cb4b6ba79887a649ffc17f45ed9bebcd0431 -- tests/test_generalized_dice_loss.py 2>/dev/null || true
