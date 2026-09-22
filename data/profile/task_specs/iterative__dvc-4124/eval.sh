#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 35e0dd920614f9f1194c82f61eeaa829f6593fb6 -- tests/unit/command/test_diff.py tests/unit/command/test_metrics.py tests/unit/command/test_params.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/command/test_diff.py b/tests/unit/command/test_diff.py
--- a/tests/unit/command/test_diff.py
+++ b/tests/unit/command/test_diff.py
@@ -114,7 +114,7 @@ def info():
 
 
 def test_show_md_empty():
-    assert _show_md({}) == ("| Status   | Path   |\n" "|----------|--------|")
+    assert _show_md({}) == ("| Status   | Path   |\n|----------|--------|\n")
 
 
 def test_show_md():
@@ -138,5 +138,5 @@ def test_show_md():
         "| deleted  | data{sep}bar |\n"
         "| deleted  | data{sep}foo |\n"
         "| deleted  | zoo      |\n"
-        "| modified | file     |"
+        "| modified | file     |\n"
     ).format(sep=os.path.sep)
diff --git a/tests/unit/command/test_metrics.py b/tests/unit/command/test_metrics.py
--- a/tests/unit/command/test_metrics.py
+++ b/tests/unit/command/test_metrics.py
@@ -171,7 +171,8 @@ def test_metrics_diff_markdown_empty():
     assert _show_diff({}, markdown=True) == textwrap.dedent(
         """\
         | Path   | Metric   | Value   | Change   |
-        |--------|----------|---------|----------|"""
+        |--------|----------|---------|----------|
+        """
     )
 
 
@@ -191,7 +192,8 @@ def test_metrics_diff_markdown():
         |--------------|----------|---------|--------------------|
         | metrics.yaml | a.b.c    | 2       | 1                  |
         | metrics.yaml | a.d.e    | 4       | 1                  |
-        | metrics.yaml | x.b      | 6       | diff not supported |"""
+        | metrics.yaml | x.b      | 6       | diff not supported |
+        """
     )
 
 
diff --git a/tests/unit/command/test_params.py b/tests/unit/command/test_params.py
--- a/tests/unit/command/test_params.py
+++ b/tests/unit/command/test_params.py
@@ -129,7 +129,8 @@ def test_params_diff_markdown_empty():
     assert _show_diff({}, markdown=True) == textwrap.dedent(
         """\
         | Path   | Param   | Old   | New   |
-        |--------|---------|-------|-------|"""
+        |--------|---------|-------|-------|
+        """
     )
 
 
@@ -149,7 +150,8 @@ def test_params_diff_markdown():
         |-------------|---------|-------|-------|
         | params.yaml | a.b.c   | 1     | None  |
         | params.yaml | a.d.e   | None  | 4     |
-        | params.yaml | x.b     | 5     | 6     |"""
+        | params.yaml | x.b     | 5     | 6     |
+        """
     )
 
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/unit/command/test_diff.py::test_show_md_empty tests/unit/command/test_diff.py::test_show_md tests/unit/command/test_metrics.py::test_metrics_diff_markdown_empty tests/unit/command/test_params.py::test_params_diff_markdown_empty tests/unit/command/test_metrics.py::test_metrics_diff_markdown tests/unit/command/test_params.py::test_params_diff_markdown tests/unit/command/test_params.py::test_params_diff_sorted tests/unit/command/test_params.py::test_params_diff tests/unit/command/test_metrics.py::test_metrics_show_raw_diff tests/unit/command/test_diff.py::test_no_changes tests/unit/command/test_metrics.py::test_metrics_diff_no_changes tests/unit/command/test_metrics.py::test_metrics_show tests/unit/command/test_metrics.py::test_metrics_diff_with_old tests/unit/command/test_metrics.py::test_metrics_diff_deleted_metric tests/unit/command/test_params.py::test_params_diff_no_changes tests/unit/command/test_metrics.py::test_metrics_diff_sorted tests/unit/command/test_params.py::test_params_diff_unchanged tests/unit/command/test_metrics.py::test_metrics_diff_precision tests/unit/command/test_metrics.py::test_metrics_diff_new_metric tests/unit/command/test_diff.py::test_show_hash tests/unit/command/test_params.py::test_params_diff_list tests/unit/command/test_params.py::test_params_diff_deleted tests/unit/command/test_diff.py::test_show_json tests/unit/command/test_params.py::test_params_diff_new tests/unit/command/test_diff.py::test_show_json_and_hash tests/unit/command/test_metrics.py::test_metrics_diff_no_path tests/unit/command/test_metrics.py::test_metrics_diff_no_diff tests/unit/command/test_params.py::test_params_diff_prec tests/unit/command/test_params.py::test_params_diff_no_path tests/unit/command/test_params.py::test_params_diff_changed tests/unit/command/test_metrics.py::test_metrics_diff tests/unit/command/test_diff.py::test_default tests/unit/command/test_params.py::test_params_diff_show_json tests/unit/command/test_metrics.py::test_metrics_show_json_diff
: '>>>>> End Test Output'
git checkout 35e0dd920614f9f1194c82f61eeaa829f6593fb6 -- tests/unit/command/test_diff.py tests/unit/command/test_metrics.py tests/unit/command/test_params.py 2>/dev/null || true
