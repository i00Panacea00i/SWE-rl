#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 5657b8f2d297e2d2b09017cf9f57dad2a72186f4 -- tests/test_handler_stats.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_handler_stats.py b/tests/test_handler_stats.py
--- a/tests/test_handler_stats.py
+++ b/tests/test_handler_stats.py
@@ -20,12 +20,23 @@
 
 import torch
 from ignite.engine import Engine, Events
+from parameterized import parameterized
 
 from monai.handlers import StatsHandler
 
 
+def get_event_filter(e):
+    def event_filter(_, event):
+        if event in e:
+            return True
+        return False
+
+    return event_filter
+
+
 class TestHandlerStats(unittest.TestCase):
-    def test_metrics_print(self):
+    @parameterized.expand([[True], [get_event_filter([1, 2])]])
+    def test_metrics_print(self, epoch_log):
         log_stream = StringIO()
         log_handler = logging.StreamHandler(log_stream)
         log_handler.setLevel(logging.INFO)
@@ -48,10 +59,11 @@ def _update_metric(engine):
         logger = logging.getLogger(key_to_handler)
         logger.setLevel(logging.INFO)
         logger.addHandler(log_handler)
-        stats_handler = StatsHandler(iteration_log=False, epoch_log=True, name=key_to_handler)
+        stats_handler = StatsHandler(iteration_log=False, epoch_log=epoch_log, name=key_to_handler)
         stats_handler.attach(engine)
 
-        engine.run(range(3), max_epochs=2)
+        max_epochs = 4
+        engine.run(range(3), max_epochs=max_epochs)
 
         # check logging output
         output_str = log_stream.getvalue()
@@ -61,9 +73,13 @@ def _update_metric(engine):
         for line in output_str.split("\n"):
             if has_key_word.match(line):
                 content_count += 1
-        self.assertTrue(content_count > 0)
+        if epoch_log is True:
+            self.assertTrue(content_count == max_epochs)
+        else:
+            self.assertTrue(content_count == 2)  # 2 = len([1, 2]) from event_filter
 
-    def test_loss_print(self):
+    @parameterized.expand([[True], [get_event_filter([1, 3])]])
+    def test_loss_print(self, iteration_log):
         log_stream = StringIO()
         log_handler = logging.StreamHandler(log_stream)
         log_handler.setLevel(logging.INFO)
@@ -80,10 +96,14 @@ def _train_func(engine, batch):
         logger = logging.getLogger(key_to_handler)
         logger.setLevel(logging.INFO)
         logger.addHandler(log_handler)
-        stats_handler = StatsHandler(iteration_log=True, epoch_log=False, name=key_to_handler, tag_name=key_to_print)
+        stats_handler = StatsHandler(
+            iteration_log=iteration_log, epoch_log=False, name=key_to_handler, tag_name=key_to_print
+        )
         stats_handler.attach(engine)
 
-        engine.run(range(3), max_epochs=2)
+        num_iters = 3
+        max_epochs = 2
+        engine.run(range(num_iters), max_epochs=max_epochs)
 
         # check logging output
         output_str = log_stream.getvalue()
@@ -93,7 +113,10 @@ def _train_func(engine, batch):
         for line in output_str.split("\n"):
             if has_key_word.match(line):
                 content_count += 1
-        self.assertTrue(content_count > 0)
+        if iteration_log is True:
+            self.assertTrue(content_count == num_iters * max_epochs)
+        else:
+            self.assertTrue(content_count == 2)  # 2 = len([1, 3]) from event_filter
 
     def test_loss_dict(self):
         log_stream = StringIO()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_handler_stats.py::TestHandlerStats::test_metrics_print_1 tests/test_handler_stats.py::TestHandlerStats::test_loss_print_1 tests/test_handler_stats.py::TestHandlerStats::test_loss_dict tests/test_handler_stats.py::TestHandlerStats::test_metrics_print_0 tests/test_handler_stats.py::TestHandlerStats::test_exception tests/test_handler_stats.py::TestHandlerStats::test_attributes_print tests/test_handler_stats.py::TestHandlerStats::test_loss_file tests/test_handler_stats.py::TestHandlerStats::test_default_logger tests/test_handler_stats.py::TestHandlerStats::test_loss_print_0
: '>>>>> End Test Output'
git checkout 5657b8f2d297e2d2b09017cf9f57dad2a72186f4 -- tests/test_handler_stats.py 2>/dev/null || true
