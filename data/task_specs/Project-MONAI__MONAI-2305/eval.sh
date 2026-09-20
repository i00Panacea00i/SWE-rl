#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout be87f318286e2d5d32189c2c4ee21e127f907579 -- tests/test_deepgrow_interaction.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_deepgrow_interaction.py b/tests/test_deepgrow_interaction.py
--- a/tests/test_deepgrow_interaction.py
+++ b/tests/test_deepgrow_interaction.py
@@ -16,9 +16,17 @@
 from monai.apps.deepgrow.interaction import Interaction
 from monai.data import Dataset
 from monai.engines import SupervisedTrainer
+from monai.engines.utils import IterationEvents
 from monai.transforms import Activationsd, Compose, ToNumpyd
 
 
+def add_one(engine):
+    if engine.state.best_metric is -1:
+        engine.state.best_metric = 0
+    else:
+        engine.state.best_metric = engine.state.best_metric + 1
+
+
 class TestInteractions(unittest.TestCase):
     def run_interaction(self, train, compose):
         data = []
@@ -47,9 +55,12 @@ def run_interaction(self, train, compose):
             loss_function=loss,
             iteration_update=i,
         )
+        engine.add_event_handler(IterationEvents.INNER_ITERATION_STARTED, add_one)
+        engine.add_event_handler(IterationEvents.INNER_ITERATION_COMPLETED, add_one)
 
         engine.run()
         self.assertIsNotNone(engine.state.batch.get("probability"), "Probability is missing")
+        self.assertEqual(engine.state.best_metric, 9)
 
     def test_train_interaction(self):
         self.run_interaction(train=True, compose=True)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_deepgrow_interaction.py::TestInteractions::test_val_interaction tests/test_deepgrow_interaction.py::TestInteractions::test_train_interaction
: '>>>>> End Test Output'
git checkout be87f318286e2d5d32189c2c4ee21e127f907579 -- tests/test_deepgrow_interaction.py 2>/dev/null || true
