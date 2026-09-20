#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 167a3206c9007d367cffc4a2a667ea4da2e10e37 -- tests/test_handler_metrics_saver.py tests/test_handler_metrics_saver_dist.py tests/test_write_metrics_reports.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_handler_metrics_saver.py b/tests/test_handler_metrics_saver.py
--- a/tests/test_handler_metrics_saver.py
+++ b/tests/test_handler_metrics_saver.py
@@ -66,7 +66,7 @@ def _save_metrics(engine):
                 f_csv = csv.reader(f)
                 for i, row in enumerate(f_csv):
                     if i > 0:
-                        self.assertEqual(row, [f"filepath{i}\t{float(i)}\t{float(i + 1)}\t{i + 0.5}"])
+                        self.assertEqual(row, [f"filepath{i}\t{float(i):.4f}\t{float(i + 1):.4f}\t{i + 0.5:.4f}"])
             self.assertTrue(os.path.exists(os.path.join(tempdir, "metric3_summary.csv")))
             # check the metric_summary.csv and content
             with open(os.path.join(tempdir, "metric4_summary.csv")) as f:
diff --git a/tests/test_handler_metrics_saver_dist.py b/tests/test_handler_metrics_saver_dist.py
--- a/tests/test_handler_metrics_saver_dist.py
+++ b/tests/test_handler_metrics_saver_dist.py
@@ -95,7 +95,7 @@ def _all_gather(engine):
                 f_csv = csv.reader(f)
                 for i, row in enumerate(f_csv):
                     if i > 0:
-                        expected = [f"{fnames[i-1]}\t{float(i)}\t{float(i + 1)}\t{i + 0.5}"]
+                        expected = [f"{fnames[i-1]}\t{float(i):.4f}\t{float(i + 1):.4f}\t{i + 0.5:.4f}"]
                         self.assertEqual(row, expected)
             self.assertTrue(os.path.exists(os.path.join(tempdir, "metric3_summary.csv")))
             # check the metric_summary.csv and content
diff --git a/tests/test_write_metrics_reports.py b/tests/test_write_metrics_reports.py
--- a/tests/test_write_metrics_reports.py
+++ b/tests/test_write_metrics_reports.py
@@ -45,7 +45,7 @@ def test_content(self):
                 f_csv = csv.reader(f)
                 for i, row in enumerate(f_csv):
                     if i > 0:
-                        self.assertEqual(row, [f"filepath{i}\t{float(i)}\t{float(i + 1)}\t{i + 0.5}"])
+                        self.assertEqual(row, [f"filepath{i}\t{float(i):.4f}\t{float(i + 1):.4f}\t{i + 0.5:.4f}"])
             self.assertTrue(os.path.exists(os.path.join(tempdir, "metric3_summary.csv")))
             # check the metric_summary.csv and content
             with open(os.path.join(tempdir, "metric3_summary.csv")) as f:

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_handler_metrics_saver.py::TestHandlerMetricsSaver::test_content tests/test_handler_metrics_saver_dist.py::DistributedMetricsSaver::test_content tests/test_write_metrics_reports.py::TestWriteMetricsReports::test_content
: '>>>>> End Test Output'
git checkout 167a3206c9007d367cffc4a2a667ea4da2e10e37 -- tests/test_handler_metrics_saver.py tests/test_handler_metrics_saver_dist.py tests/test_write_metrics_reports.py 2>/dev/null || true
