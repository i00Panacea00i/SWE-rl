#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 922eb20e44ba4da8e0bb3ccc9e8da5fd41d9717b -- tests/unit/command/test_plots.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/command/test_plots.py b/tests/unit/command/test_plots.py
--- a/tests/unit/command/test_plots.py
+++ b/tests/unit/command/test_plots.py
@@ -1,5 +1,6 @@
 import os
 import posixpath
+from pathlib import Path
 
 import pytest
 
@@ -149,12 +150,31 @@ def test_plots_diff_open(tmp_dir, dvc, mocker, capsys, plots_data):
     mocker.patch("dvc.command.plots.render", return_value=index_path)
 
     assert cmd.run() == 0
-    mocked_open.assert_called_once_with(index_path)
+    mocked_open.assert_called_once_with(index_path.as_uri())
 
     out, _ = capsys.readouterr()
     assert index_path.as_uri() in out
 
 
+def test_plots_diff_open_WSL(tmp_dir, dvc, mocker, plots_data):
+    mocked_open = mocker.patch("webbrowser.open", return_value=True)
+    mocked_uname_result = mocker.MagicMock()
+    mocked_uname_result.release = "Microsoft"
+    mocker.patch("platform.uname", return_value=mocked_uname_result)
+
+    cli_args = parse_args(
+        ["plots", "diff", "--targets", "plots.csv", "--open"]
+    )
+    cmd = cli_args.func(cli_args)
+    mocker.patch("dvc.repo.plots.diff.diff", return_value=plots_data)
+
+    index_path = tmp_dir / "dvc_plots" / "index.html"
+    mocker.patch("dvc.command.plots.render", return_value=index_path)
+
+    assert cmd.run() == 0
+    mocked_open.assert_called_once_with(Path("dvc_plots") / "index.html")
+
+
 def test_plots_diff_open_failed(tmp_dir, dvc, mocker, capsys, plots_data):
     mocked_open = mocker.patch("webbrowser.open", return_value=False)
     cli_args = parse_args(
@@ -167,7 +187,7 @@ def test_plots_diff_open_failed(tmp_dir, dvc, mocker, capsys, plots_data):
 
     assert cmd.run() == 1
     expected_url = tmp_dir / "dvc_plots" / "index.html"
-    mocked_open.assert_called_once_with(expected_url)
+    mocked_open.assert_called_once_with(expected_url.as_uri())
 
     error_message = "Failed to open. Please try opening it manually."
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/unit/command/test_plots.py::test_plots_diff_open_WSL tests/unit/command/test_plots.py::test_plots_diff_open_failed tests/unit/command/test_plots.py::test_plots_diff_open 'tests/unit/command/test_plots.py::test_plots_path_is_quoted_and_resolved_properly[quote]' tests/unit/command/test_plots.py::test_plots_show_vega 'tests/unit/command/test_plots.py::test_should_call_render[some_out]' 'tests/unit/command/test_plots.py::test_should_call_render[to/subdir]' tests/unit/command/test_plots.py::test_plots_diff 'tests/unit/command/test_plots.py::test_plots_path_is_quoted_and_resolved_properly[resolve]' tests/unit/command/test_plots.py::test_plots_diff_vega 'tests/unit/command/test_plots.py::test_should_call_render[None]'
: '>>>>> End Test Output'
git checkout 922eb20e44ba4da8e0bb3ccc9e8da5fd41d9717b -- tests/unit/command/test_plots.py 2>/dev/null || true
