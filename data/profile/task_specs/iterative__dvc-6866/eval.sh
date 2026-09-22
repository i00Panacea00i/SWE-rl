#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 922eb20e44ba4da8e0bb3ccc9e8da5fd41d9717b -- tests/unit/render/test_vega.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/render/test_vega.py b/tests/unit/render/test_vega.py
--- a/tests/unit/render/test_vega.py
+++ b/tests/unit/render/test_vega.py
@@ -451,3 +451,29 @@ def test_find_vega(tmp_dir, dvc):
         first(plot_content["layer"])["encoding"]["x"]["field"] == INDEX_FIELD
     )
     assert first(plot_content["layer"])["encoding"]["y"]["field"] == "y"
+
+
+@pytest.mark.parametrize(
+    "template_path, target_name",
+    [
+        (os.path.join(".dvc", "plots", "template.json"), "template"),
+        (os.path.join(".dvc", "plots", "template.json"), "template.json"),
+        (
+            os.path.join(".dvc", "plots", "subdir", "template.json"),
+            os.path.join("subdir", "template.json"),
+        ),
+        (
+            os.path.join(".dvc", "plots", "subdir", "template.json"),
+            os.path.join("subdir", "template"),
+        ),
+        ("template.json", "template.json"),
+    ],
+)
+def test_should_resolve_template(tmp_dir, dvc, template_path, target_name):
+    os.makedirs(os.path.abspath(os.path.dirname(template_path)), exist_ok=True)
+    with open(template_path, "w", encoding="utf-8") as fd:
+        fd.write("template_content")
+
+    assert dvc.plots.templates._find_in_project(
+        target_name
+    ) == os.path.abspath(template_path)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/unit/render/test_vega.py::test_should_resolve_template[.dvc/plots/subdir/template.json-subdir/template.json]' 'tests/unit/render/test_vega.py::test_should_resolve_template[.dvc/plots/template.json-template]' 'tests/unit/render/test_vega.py::test_should_resolve_template[.dvc/plots/subdir/template.json-subdir/template]' 'tests/unit/render/test_vega.py::test_should_resolve_template[template.json-template.json]' 'tests/unit/render/test_vega.py::test_should_resolve_template[.dvc/plots/template.json-template.json]' tests/unit/render/test_vega.py::test_group_plots_data 'tests/unit/render/test_vega.py::test_matches[.csv-True]' 'tests/unit/render/test_vega.py::test_finding_lists[dictionary2-expected_result2]' 'tests/unit/render/test_vega.py::test_matches[.gif-False]' tests/unit/render/test_vega.py::test_multiple_columns tests/unit/render/test_vega.py::test_metric_missing tests/unit/render/test_vega.py::test_plot_choose_columns 'tests/unit/render/test_vega.py::test_finding_lists[dictionary1-expected_result1]' tests/unit/render/test_vega.py::test_choose_axes tests/unit/render/test_vega.py::test_raise_on_no_template 'tests/unit/render/test_vega.py::test_finding_lists[dictionary0-expected_result0]' tests/unit/render/test_vega.py::test_find_data_in_dict tests/unit/render/test_vega.py::test_find_vega tests/unit/render/test_vega.py::test_multiple_revs_default tests/unit/render/test_vega.py::test_bad_template 'tests/unit/render/test_vega.py::test_matches[.tsv-True]' tests/unit/render/test_vega.py::test_plot_default_choose_column tests/unit/render/test_vega.py::test_custom_template 'tests/unit/render/test_vega.py::test_matches[.png-False]' 'tests/unit/render/test_vega.py::test_matches[.jpg-False]' tests/unit/render/test_vega.py::test_one_column 'tests/unit/render/test_vega.py::test_matches[.json-True]' 'tests/unit/render/test_vega.py::test_matches[.jpeg-False]' 'tests/unit/render/test_vega.py::test_matches[.yaml-True]' tests/unit/render/test_vega.py::test_raise_on_wrong_field tests/unit/render/test_vega.py::test_confusion
: '>>>>> End Test Output'
git checkout 922eb20e44ba4da8e0bb3ccc9e8da5fd41d9717b -- tests/unit/render/test_vega.py 2>/dev/null || true
