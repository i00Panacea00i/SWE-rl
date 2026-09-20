#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 13bf996409eb04b2fddf753f6aedb2a4b71ccec3 -- tests/test_handler_mean_dice.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_handler_mean_dice.py b/tests/test_handler_mean_dice.py
--- a/tests/test_handler_mean_dice.py
+++ b/tests/test_handler_mean_dice.py
@@ -40,7 +40,7 @@ def _val_func(engine, batch):
         dice_metric.update([y_pred, y])
 
         y_pred = [torch.Tensor([[0], [1]]), torch.Tensor([[1], [0]])]
-        y = [torch.Tensor([[0], [1]]), torch.Tensor([[1], [0]])]
+        y = torch.Tensor([[[0], [1]], [[1], [0]]])
         dice_metric.update([y_pred, y])
 
         avg_dice = dice_metric.compute()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_handler_mean_dice.py::TestHandlerMeanDice::test_compute_0 tests/test_handler_mean_dice.py::TestHandlerMeanDice::test_compute_1 tests/test_handler_mean_dice.py::TestHandlerMeanDice::test_shape_mismatch_0 tests/test_handler_mean_dice.py::TestHandlerMeanDice::test_shape_mismatch_1
: '>>>>> End Test Output'
git checkout 13bf996409eb04b2fddf753f6aedb2a4b71ccec3 -- tests/test_handler_mean_dice.py 2>/dev/null || true
