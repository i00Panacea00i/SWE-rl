#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 63972c3d120d9f076f642a19382a247d5d5855a5 -- tests/unit/command/test_plots.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/command/test_plots.py b/tests/unit/command/test_plots.py
--- a/tests/unit/command/test_plots.py
+++ b/tests/unit/command/test_plots.py
@@ -13,7 +13,7 @@ def test_metrics_diff(dvc, mocker):
             "template",
             "--targets",
             "datafile",
-            "--show-json",
+            "--show-vega",
             "-x",
             "x_field",
             "-y",
@@ -32,7 +32,9 @@ def test_metrics_diff(dvc, mocker):
     assert cli_args.func == CmdPlotsDiff
 
     cmd = cli_args.func(cli_args)
-    m = mocker.patch("dvc.repo.plots.diff.diff", return_value={})
+    m = mocker.patch(
+        "dvc.repo.plots.diff.diff", return_value={"datafile": "filledtemplate"}
+    )
 
     assert cmd.run() == 0
 
@@ -59,7 +61,7 @@ def test_metrics_show(dvc, mocker):
             "result.extension",
             "-t",
             "template",
-            "--show-json",
+            "--show-vega",
             "--no-csv-header",
             "datafile",
         ]
@@ -68,7 +70,9 @@ def test_metrics_show(dvc, mocker):
 
     cmd = cli_args.func(cli_args)
 
-    m = mocker.patch("dvc.repo.plots.show.show", return_value={})
+    m = mocker.patch(
+        "dvc.repo.plots.show.show", return_value={"datafile": "filledtemplate"}
+    )
 
     assert cmd.run() == 0
 
@@ -85,13 +89,21 @@ def test_metrics_show(dvc, mocker):
     )
 
 
-def test_plots_show_json(dvc, mocker, caplog):
+def test_plots_show_vega(dvc, mocker, caplog):
     cli_args = parse_args(
-        ["plots", "diff", "HEAD~10", "HEAD~1", "--show-json"]
+        [
+            "plots",
+            "diff",
+            "HEAD~10",
+            "HEAD~1",
+            "--show-vega",
+            "--targets",
+            "plots.csv",
+        ]
     )
     cmd = cli_args.func(cli_args)
     mocker.patch(
         "dvc.repo.plots.diff.diff", return_value={"plots.csv": "plothtml"}
     )
     assert cmd.run() == 0
-    assert '{"plots.csv": "plothtml"}\n' in caplog.text
+    assert "plothtml" in caplog.text

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/unit/command/test_plots.py::test_metrics_diff tests/unit/command/test_plots.py::test_plots_show_vega tests/unit/command/test_plots.py::test_metrics_show
: '>>>>> End Test Output'
git checkout 63972c3d120d9f076f642a19382a247d5d5855a5 -- tests/unit/command/test_plots.py 2>/dev/null || true
