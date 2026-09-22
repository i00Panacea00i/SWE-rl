#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8ef52f92ee262bdc76b24955c72a5df18b6eb1a5 -- tests/func/test_metrics.py tests/func/test_tree.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_metrics.py b/tests/func/test_metrics.py
--- a/tests/func/test_metrics.py
+++ b/tests/func/test_metrics.py
@@ -279,6 +279,33 @@ def test_formatted_output(self):
         assert expected_txt in stdout
         assert expected_json in stdout
 
+    def test_show_all_should_be_current_dir_agnostic(self):
+        os.chdir(self.DATA_DIR)
+
+        metrics = self.dvc.metrics.show(all_branches=True)
+        self.assertMetricsHaveRelativePaths(metrics)
+
+    def assertMetricsHaveRelativePaths(self, metrics):
+        root_relpath = os.path.relpath(self.dvc.root_dir)
+        metric_path = os.path.join(root_relpath, "metric")
+        metric_json_path = os.path.join(root_relpath, "metric_json")
+        metric_tsv_path = os.path.join(root_relpath, "metric_tsv")
+        metric_htsv_path = os.path.join(root_relpath, "metric_htsv")
+        metric_csv_path = os.path.join(root_relpath, "metric_csv")
+        metric_hcsv_path = os.path.join(root_relpath, "metric_hcsv")
+        for branch in ["bar", "baz", "foo"]:
+            self.assertEqual(
+                set(metrics[branch].keys()),
+                {
+                    metric_path,
+                    metric_json_path,
+                    metric_tsv_path,
+                    metric_htsv_path,
+                    metric_csv_path,
+                    metric_hcsv_path,
+                },
+            )
+
 
 class TestMetricsRecursive(TestDvc):
     def setUp(self):
diff --git a/tests/func/test_tree.py b/tests/func/test_tree.py
--- a/tests/func/test_tree.py
+++ b/tests/func/test_tree.py
@@ -97,38 +97,66 @@ def convert_to_sets(walk_results):
 
 class TestWalkInNoSCM(AssertWalkEqualMixin, TestDir):
     def test(self):
-        tree = WorkingTree()
+        tree = WorkingTree(self._root_dir)
         self.assertWalkEqual(
-            tree.walk("."),
+            tree.walk(self._root_dir),
             [
-                (".", ["data_dir"], ["code.py", "bar", "тест", "foo"]),
-                (join("data_dir"), ["data_sub_dir"], ["data"]),
-                (join("data_dir", "data_sub_dir"), [], ["data_sub"]),
+                (
+                    self._root_dir,
+                    ["data_dir"],
+                    ["code.py", "bar", "тест", "foo"],
+                ),
+                (join(self._root_dir, "data_dir"), ["data_sub_dir"], ["data"]),
+                (
+                    join(self._root_dir, "data_dir", "data_sub_dir"),
+                    [],
+                    ["data_sub"],
+                ),
             ],
         )
 
     def test_subdir(self):
-        tree = WorkingTree()
+        tree = WorkingTree(self._root_dir)
         self.assertWalkEqual(
             tree.walk(join("data_dir", "data_sub_dir")),
-            [(join("data_dir", "data_sub_dir"), [], ["data_sub"])],
+            [
+                (
+                    join(self._root_dir, "data_dir", "data_sub_dir"),
+                    [],
+                    ["data_sub"],
+                )
+            ],
         )
 
 
 class TestWalkInGit(AssertWalkEqualMixin, TestGit):
     def test_nobranch(self):
-        tree = WorkingTree()
+        tree = WorkingTree(self._root_dir)
         self.assertWalkEqual(
             tree.walk("."),
             [
-                (".", ["data_dir"], ["bar", "тест", "code.py", "foo"]),
-                ("data_dir", ["data_sub_dir"], ["data"]),
-                (join("data_dir", "data_sub_dir"), [], ["data_sub"]),
+                (
+                    self._root_dir,
+                    ["data_dir"],
+                    ["bar", "тест", "code.py", "foo"],
+                ),
+                (join(self._root_dir, "data_dir"), ["data_sub_dir"], ["data"]),
+                (
+                    join(self._root_dir, "data_dir", "data_sub_dir"),
+                    [],
+                    ["data_sub"],
+                ),
             ],
         )
         self.assertWalkEqual(
             tree.walk(join("data_dir", "data_sub_dir")),
-            [(join("data_dir", "data_sub_dir"), [], ["data_sub"])],
+            [
+                (
+                    join(self._root_dir, "data_dir", "data_sub_dir"),
+                    [],
+                    ["data_sub"],
+                )
+            ],
         )
 
     def test_branch(self):
@@ -139,12 +167,22 @@ def test_branch(self):
         self.assertWalkEqual(
             tree.walk("."),
             [
-                (".", ["data_dir"], ["code.py"]),
-                ("data_dir", ["data_sub_dir"], []),
-                (join("data_dir", "data_sub_dir"), [], ["data_sub"]),
+                (self._root_dir, ["data_dir"], ["code.py"]),
+                (join(self._root_dir, "data_dir"), ["data_sub_dir"], []),
+                (
+                    join(self._root_dir, "data_dir", "data_sub_dir"),
+                    [],
+                    ["data_sub"],
+                ),
             ],
         )
         self.assertWalkEqual(
             tree.walk(join("data_dir", "data_sub_dir")),
-            [(join("data_dir", "data_sub_dir"), [], ["data_sub"])],
+            [
+                (
+                    join(self._root_dir, "data_dir", "data_sub_dir"),
+                    [],
+                    ["data_sub"],
+                )
+            ],
         )

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_tree.py::TestWalkInGit::test_nobranch tests/func/test_tree.py::TestWalkInGit::test_branch tests/func/test_metrics.py::TestMetricsCLI::test_show_all_should_be_current_dir_agnostic tests/func/test_tree.py::TestWalkInNoSCM::test_subdir tests/func/test_metrics.py::TestMetrics::test_show_all_should_be_current_dir_agnostic tests/func/test_tree.py::TestWorkingTree::test_isdir tests/func/test_metrics.py::TestMetricsRecursive::test tests/func/test_metrics.py::TestMetrics::test_formatted_output tests/func/test_metrics.py::TestMetrics::test_xpath_is_none tests/func/test_metrics.py::TestMetricsType::test_show tests/func/test_metrics.py::TestMetricsCLI::test_xpath_all_columns tests/func/test_metrics.py::TestNoMetrics::test tests/func/test_tree.py::TestWorkingTree::test_open tests/func/test_metrics.py::TestMetricsCLI::test_xpath_all_rows tests/func/test_metrics.py::TestMetricsCLI::test_dir tests/func/test_metrics.py::TestMetricsCLI::test_xpath_is_none tests/func/test_tree.py::TestGitTree::test_exists tests/func/test_metrics.py::TestMetricsCLI::test_xpath_is_empty tests/func/test_metrics.py::TestMetricsCLI::test_type_case_normalized tests/func/test_metrics.py::TestMetricsCLI::test_binary tests/func/test_metrics.py::TestNoMetrics::test_cli tests/func/test_metrics.py::TestMetrics::test_xpath_all tests/func/test_tree.py::TestWorkingTree::test_isfile tests/func/test_metrics.py::TestMetricsReproCLI::test tests/func/test_tree.py::TestGitTree::test_isfile tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_add tests/func/test_metrics.py::TestCachedMetrics::test_run tests/func/test_metrics.py::TestMetrics::test_show tests/func/test_metrics.py::TestMetricsReproCLI::test_dir tests/func/test_metrics.py::TestMetrics::test_xpath_all_columns tests/func/test_metrics.py::TestMetrics::test_unknown_type_ignored tests/func/test_metrics.py::TestMetricsReproCLI::test_binary tests/func/test_metrics.py::TestMetricsCLI::test_xpath_all_with_header tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_modify tests/func/test_tree.py::TestGitTree::test_open tests/func/test_metrics.py::TestMetricsCLI::test_show tests/func/test_tree.py::TestWorkingTree::test_exists tests/func/test_metrics.py::TestMetricsCLI::test_formatted_output tests/func/test_metrics.py::TestMetricsCLI::test_xpath_all tests/func/test_metrics.py::TestMetrics::test_type_case_normalized tests/func/test_metrics.py::TestMetricsCLI::test tests/func/test_tree.py::TestGitTree::test_isdir tests/func/test_metrics.py::TestMetrics::test_xpath_is_empty tests/func/test_metrics.py::TestCachedMetrics::test_add tests/func/test_tree.py::TestWalkInNoSCM::test tests/func/test_metrics.py::TestMetricsCLI::test_non_existing tests/func/test_metrics.py::TestMetrics::test_xpath_all_rows tests/func/test_metrics.py::TestMetrics::test_xpath_all_with_header tests/func/test_metrics.py::TestMetricsCLI::test_unknown_type_ignored tests/func/test_metrics.py::TestMetricsCLI::test_wrong_type_show
: '>>>>> End Test Output'
git checkout 8ef52f92ee262bdc76b24955c72a5df18b6eb1a5 -- tests/func/test_metrics.py tests/func/test_tree.py 2>/dev/null || true
