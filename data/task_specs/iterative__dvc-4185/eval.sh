#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 0899b277c02082ffc24bb732e8a7cf3ef4333948 -- tests/func/test_run_multistage.py tests/unit/dependency/test_params.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_run_multistage.py b/tests/func/test_run_multistage.py
--- a/tests/func/test_run_multistage.py
+++ b/tests/func/test_run_multistage.py
@@ -244,7 +244,7 @@ def test_run_params_default(tmp_dir, dvc):
         params=["nested.nested1.nested2"],
         cmd="cat params.yaml",
     )
-    isinstance(stage.deps[0], ParamsDependency)
+    assert isinstance(stage.deps[0], ParamsDependency)
     assert stage.deps[0].params == ["nested.nested1.nested2"]
 
     lockfile = stage.dvcfile._lockfile
diff --git a/tests/unit/dependency/test_params.py b/tests/unit/dependency/test_params.py
--- a/tests/unit/dependency/test_params.py
+++ b/tests/unit/dependency/test_params.py
@@ -4,6 +4,7 @@
 from dvc.dependency import ParamsDependency, loadd_from, loads_params
 from dvc.dependency.param import BadParamFileError, MissingParamsError
 from dvc.stage import Stage
+from dvc.utils.yaml import load_yaml
 
 PARAMS = {
     "foo": 1,
@@ -11,6 +12,7 @@
     "baz": "str",
     "qux": None,
 }
+DEFAULT_PARAMS_FILE = ParamsDependency.DEFAULT_PARAMS_FILE
 
 
 def test_loads_params(dvc):
@@ -63,7 +65,7 @@ def test_loadd_from(dvc):
 def test_dumpd_with_info(dvc):
     dep = ParamsDependency(Stage(dvc), None, PARAMS)
     assert dep.dumpd() == {
-        "path": "params.yaml",
+        "path": DEFAULT_PARAMS_FILE,
         "params": PARAMS,
     }
 
@@ -71,7 +73,7 @@ def test_dumpd_with_info(dvc):
 def test_dumpd_without_info(dvc):
     dep = ParamsDependency(Stage(dvc), None, list(PARAMS.keys()))
     assert dep.dumpd() == {
-        "path": "params.yaml",
+        "path": DEFAULT_PARAMS_FILE,
         "params": list(PARAMS.keys()),
     }
 
@@ -82,7 +84,7 @@ def test_read_params_nonexistent_file(dvc):
 
 
 def test_read_params_unsupported_format(tmp_dir, dvc):
-    tmp_dir.gen("params.yaml", b"\0\1\2\3\4\5\6\7")
+    tmp_dir.gen(DEFAULT_PARAMS_FILE, b"\0\1\2\3\4\5\6\7")
     dep = ParamsDependency(Stage(dvc), None, ["foo"])
     with pytest.raises(BadParamFileError):
         dep.read_params()
@@ -90,7 +92,8 @@ def test_read_params_unsupported_format(tmp_dir, dvc):
 
 def test_read_params_nested(tmp_dir, dvc):
     tmp_dir.gen(
-        "params.yaml", yaml.dump({"some": {"path": {"foo": ["val1", "val2"]}}})
+        DEFAULT_PARAMS_FILE,
+        yaml.dump({"some": {"path": {"foo": ["val1", "val2"]}}}),
     )
     dep = ParamsDependency(Stage(dvc), None, ["some.path.foo"])
     assert dep.read_params() == {"some.path.foo": ["val1", "val2"]}
@@ -103,7 +106,24 @@ def test_save_info_missing_config(dvc):
 
 
 def test_save_info_missing_param(tmp_dir, dvc):
-    tmp_dir.gen("params.yaml", "bar: baz")
+    tmp_dir.gen(DEFAULT_PARAMS_FILE, "bar: baz")
     dep = ParamsDependency(Stage(dvc), None, ["foo"])
     with pytest.raises(MissingParamsError):
         dep.save_info()
+
+
+@pytest.mark.parametrize(
+    "param_value",
+    ["", "false", "[]", "{}", "null", "no", "off"]
+    # we use pyyaml to load params.yaml, which only supports YAML 1.1
+    # so, some of the above are boolean values
+)
+def test_params_with_false_values(tmp_dir, dvc, param_value):
+    key = "param"
+    dep = ParamsDependency(Stage(dvc), DEFAULT_PARAMS_FILE, [key])
+    (tmp_dir / DEFAULT_PARAMS_FILE).write_text(f"{key}: {param_value}")
+
+    dep.fill_values(load_yaml(DEFAULT_PARAMS_FILE))
+
+    with dvc.state:
+        assert dep.status() == {}

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/unit/dependency/test_params.py::test_params_with_false_values[{}]' 'tests/unit/dependency/test_params.py::test_params_with_false_values[no]' 'tests/unit/dependency/test_params.py::test_params_with_false_values[[]]' 'tests/unit/dependency/test_params.py::test_params_with_false_values[false]' 'tests/unit/dependency/test_params.py::test_params_with_false_values[off]' 'tests/unit/dependency/test_params.py::test_params_with_false_values[]' 'tests/unit/dependency/test_params.py::test_params_with_false_values[null]' tests/unit/dependency/test_params.py::test_save_info_missing_config tests/unit/dependency/test_params.py::test_read_params_unsupported_format tests/unit/dependency/test_params.py::test_save_info_missing_param 'tests/func/test_run_multistage.py::test_run_without_cmd[kwargs1]' tests/unit/dependency/test_params.py::test_dumpd_with_info 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[,]' tests/unit/dependency/test_params.py::test_loads_params 'tests/unit/dependency/test_params.py::test_params_error[params1]' tests/unit/dependency/test_params.py::test_read_params_nonexistent_file 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[#]' 'tests/func/test_run_multistage.py::test_run_without_cmd[kwargs0]' 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[\]' 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[$]' tests/unit/dependency/test_params.py::test_dumpd_without_info 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[:]' 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[@:]' 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[;]' 'tests/unit/dependency/test_params.py::test_params_error[params0]' tests/unit/dependency/test_params.py::test_read_params_nested tests/unit/dependency/test_params.py::test_loadd_from 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[.]' 'tests/func/test_run_multistage.py::test_run_with_invalid_stage_name[/]'
: '>>>>> End Test Output'
git checkout 0899b277c02082ffc24bb732e8a7cf3ef4333948 -- tests/func/test_run_multistage.py tests/unit/dependency/test_params.py 2>/dev/null || true
