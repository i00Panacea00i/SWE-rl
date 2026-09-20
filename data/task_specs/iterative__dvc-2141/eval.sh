#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout c023b8da570a9b18ff26969d602011ae03ff75bf -- tests/func/test_metrics.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_metrics.py b/tests/func/test_metrics.py
--- a/tests/func/test_metrics.py
+++ b/tests/func/test_metrics.py
@@ -706,6 +706,7 @@ def _test_metrics(self, func):
                 "master": {"metrics.json": ["master"]},
                 "one": {"metrics.json": ["one"]},
                 "two": {"metrics.json": ["two"]},
+                "working tree": {"metrics.json": ["two"]},
             },
         )
 
@@ -719,6 +720,7 @@ def _test_metrics(self, func):
                 "master": {"metrics.json": ["master"]},
                 "one": {"metrics.json": ["one"]},
                 "two": {"metrics.json": ["two"]},
+                "working tree": {"metrics.json": ["two"]},
             },
         )
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_metrics.py::TestCachedMetrics::test_add tests/func/test_metrics.py::TestCachedMetrics::test_run tests/func/test_metrics.py::TestMetricsRecursive::test tests/func/test_metrics.py::TestMetrics::test_formatted_output tests/func/test_metrics.py::TestMetrics::test_xpath_is_none tests/func/test_metrics.py::TestMetricsType::test_show tests/func/test_metrics.py::TestNoMetrics::test tests/func/test_metrics.py::TestShouldDisplayMetricsEvenIfMetricIsMissing::test tests/func/test_metrics.py::TestMetricsCLI::test_dir tests/func/test_metrics.py::TestMetricsCLI::test_binary tests/func/test_metrics.py::TestMetrics::test_show_all_should_be_current_dir_agnostic tests/func/test_metrics.py::TestNoMetrics::test_cli tests/func/test_metrics.py::TestMetrics::test_xpath_all tests/func/test_metrics.py::TestMetricsReproCLI::test tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_add tests/func/test_metrics.py::TestMetrics::test_show tests/func/test_metrics.py::TestMetricsReproCLI::test_dir tests/func/test_metrics.py::TestMetrics::test_xpath_all_columns tests/func/test_metrics.py::TestMetrics::test_unknown_type_ignored tests/func/test_metrics.py::TestMetricsReproCLI::test_binary tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_modify tests/func/test_metrics.py::TestMetrics::test_type_case_normalized tests/func/test_metrics.py::TestMetricsCLI::test tests/func/test_metrics.py::TestMetrics::test_xpath_is_empty tests/func/test_metrics.py::TestMetricsCLI::test_non_existing tests/func/test_metrics.py::TestMetrics::test_xpath_all_rows tests/func/test_metrics.py::TestMetrics::test_xpath_all_with_header tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_show
: '>>>>> End Test Output'
git checkout c023b8da570a9b18ff26969d602011ae03ff75bf -- tests/func/test_metrics.py 2>/dev/null || true
