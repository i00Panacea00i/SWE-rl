#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 27bf6e292826305129e4c3e0c4418e45b45e535b -- tests/func/test_metrics.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_metrics.py b/tests/func/test_metrics.py
--- a/tests/func/test_metrics.py
+++ b/tests/func/test_metrics.py
@@ -37,6 +37,35 @@ def setUp(self):
                 fd.write("branch\n")
                 fd.write(branch)
 
+            if branch == "foo":
+                deviation_mse_train = 0.173461
+            else:
+                deviation_mse_train = 0.356245
+
+            with open("metric_json_ext", "w+") as fd:
+                json.dump(
+                    {
+                        "metrics": [
+                            {
+                                "dataset": "train",
+                                "deviation_mse": deviation_mse_train,
+                                "value_mse": 0.421601,
+                            },
+                            {
+                                "dataset": "testing",
+                                "deviation_mse": 0.289545,
+                                "value_mse": 0.297848,
+                            },
+                            {
+                                "dataset": "validation",
+                                "deviation_mse": 0.67528,
+                                "value_mse": 0.671502,
+                            },
+                        ]
+                    },
+                    fd,
+                )
+
             files = [
                 "metric",
                 "metric_json",
@@ -44,6 +73,7 @@ def setUp(self):
                 "metric_htsv",
                 "metric_csv",
                 "metric_hcsv",
+                "metric_json_ext",
             ]
 
             self.dvc.run(metrics_no_cache=files, overwrite=True)
@@ -101,6 +131,26 @@ def test_show(self):
         self.assertSequenceEqual(ret["bar"]["metric_hcsv"], ["bar"])
         self.assertSequenceEqual(ret["baz"]["metric_hcsv"], ["baz"])
 
+        ret = self.dvc.metrics.show(
+            "metric_json_ext",
+            typ="json",
+            xpath="$.metrics[?(@.deviation_mse<0.30) & (@.value_mse>0.4)]",
+            all_branches=True,
+        )
+        self.assertEqual(len(ret), 1)
+        self.assertSequenceEqual(
+            ret["foo"]["metric_json_ext"],
+            [
+                {
+                    "dataset": "train",
+                    "deviation_mse": 0.173461,
+                    "value_mse": 0.421601,
+                }
+            ],
+        )
+        self.assertRaises(KeyError, lambda: ret["bar"])
+        self.assertRaises(KeyError, lambda: ret["baz"])
+
     def test_unknown_type_ignored(self):
         ret = self.dvc.metrics.show(
             "metric_hcsv", typ="unknown", xpath="0,branch", all_branches=True
@@ -293,6 +343,7 @@ def assertMetricsHaveRelativePaths(self, metrics):
         metric_htsv_path = os.path.join(root_relpath, "metric_htsv")
         metric_csv_path = os.path.join(root_relpath, "metric_csv")
         metric_hcsv_path = os.path.join(root_relpath, "metric_hcsv")
+        metric_json_ext_path = os.path.join(root_relpath, "metric_json_ext")
         for branch in ["bar", "baz", "foo"]:
             self.assertEqual(
                 set(metrics[branch].keys()),
@@ -303,6 +354,7 @@ def assertMetricsHaveRelativePaths(self, metrics):
                     metric_htsv_path,
                     metric_csv_path,
                     metric_hcsv_path,
+                    metric_json_ext_path,
                 },
             )
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_metrics.py::TestMetrics::test_show tests/func/test_metrics.py::TestMetricsCLI::test_show tests/func/test_metrics.py::TestMetricsRecursive::test tests/func/test_metrics.py::TestMetrics::test_formatted_output tests/func/test_metrics.py::TestMetrics::test_xpath_is_none tests/func/test_metrics.py::TestMetricsType::test_show tests/func/test_metrics.py::TestMetricsCLI::test_xpath_all_columns tests/func/test_metrics.py::TestNoMetrics::test tests/func/test_metrics.py::TestMetricsCLI::test_xpath_all_rows tests/func/test_metrics.py::TestMetricsCLI::test_dir tests/func/test_metrics.py::TestMetricsCLI::test_xpath_is_none tests/func/test_metrics.py::TestMetricsCLI::test_xpath_is_empty tests/func/test_metrics.py::TestMetricsCLI::test_type_case_normalized tests/func/test_metrics.py::TestMetricsCLI::test_binary tests/func/test_metrics.py::TestMetrics::test_show_all_should_be_current_dir_agnostic tests/func/test_metrics.py::TestNoMetrics::test_cli tests/func/test_metrics.py::TestMetrics::test_xpath_all tests/func/test_metrics.py::TestMetricsReproCLI::test tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_add tests/func/test_metrics.py::TestCachedMetrics::test_run tests/func/test_metrics.py::TestMetricsCLI::test_show_all_should_be_current_dir_agnostic tests/func/test_metrics.py::TestMetricsCLI::test_xpath_all_with_header tests/func/test_metrics.py::TestMetricsReproCLI::test_dir tests/func/test_metrics.py::TestMetrics::test_xpath_all_columns tests/func/test_metrics.py::TestMetrics::test_unknown_type_ignored tests/func/test_metrics.py::TestMetricsReproCLI::test_binary tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_modify tests/func/test_metrics.py::TestMetricsCLI::test_formatted_output tests/func/test_metrics.py::TestMetricsCLI::test_xpath_all tests/func/test_metrics.py::TestMetrics::test_type_case_normalized tests/func/test_metrics.py::TestMetricsCLI::test tests/func/test_metrics.py::TestMetrics::test_xpath_is_empty tests/func/test_metrics.py::TestCachedMetrics::test_add tests/func/test_metrics.py::TestMetricsCLI::test_non_existing tests/func/test_metrics.py::TestMetrics::test_xpath_all_rows tests/func/test_metrics.py::TestMetrics::test_xpath_all_with_header tests/func/test_metrics.py::TestMetricsCLI::test_unknown_type_ignored tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_show
: '>>>>> End Test Output'
git checkout 27bf6e292826305129e4c3e0c4418e45b45e535b -- tests/func/test_metrics.py 2>/dev/null || true
