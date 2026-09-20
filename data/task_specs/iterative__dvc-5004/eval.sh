#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 7c45711e34f565330be416621037f983d0034bef -- tests/func/test_stage_resolver.py tests/unit/test_context.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_stage_resolver.py b/tests/func/test_stage_resolver.py
--- a/tests/func/test_stage_resolver.py
+++ b/tests/func/test_stage_resolver.py
@@ -337,12 +337,16 @@ def test_set(tmp_dir, dvc, value):
         }
     }
     resolver = DataResolver(dvc, PathInfo(str(tmp_dir)), d)
+    if isinstance(value, bool):
+        stringified_value = "true" if value else "false"
+    else:
+        stringified_value = str(value)
     assert_stage_equal(
         resolver.resolve(),
         {
             "stages": {
                 "build": {
-                    "cmd": f"python script.py --thresh {value}",
+                    "cmd": f"python script.py --thresh {stringified_value}",
                     "always_changed": value,
                 }
             }
diff --git a/tests/unit/test_context.py b/tests/unit/test_context.py
--- a/tests/unit/test_context.py
+++ b/tests/unit/test_context.py
@@ -411,6 +411,17 @@ def test_resolve_resolves_dict_keys():
     }
 
 
+def test_resolve_resolves_boolean_value():
+    d = {"enabled": True, "disabled": False}
+    context = Context(d)
+
+    assert context.resolve_str("${enabled}") is True
+    assert context.resolve_str("${disabled}") is False
+
+    assert context.resolve_str("--flag ${enabled}") == "--flag true"
+    assert context.resolve_str("--flag ${disabled}") == "--flag false"
+
+
 def test_merge_from_raises_if_file_not_exist(tmp_dir, dvc):
     context = Context(foo="bar")
     with pytest.raises(ParamsFileNotFound):

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail 'tests/func/test_stage_resolver.py::test_set[True]' 'tests/func/test_stage_resolver.py::test_set[False]' tests/unit/test_context.py::test_resolve_resolves_boolean_value tests/unit/test_context.py::test_select tests/unit/test_context.py::test_context_list tests/unit/test_context.py::test_merge_list 'tests/func/test_stage_resolver.py::test_set[To' tests/unit/test_context.py::test_track 'tests/func/test_stage_resolver.py::test_set[value]' 'tests/func/test_stage_resolver.py::test_set[3.141592653589793]' 'tests/func/test_stage_resolver.py::test_set[None]' tests/unit/test_context.py::test_select_unwrap tests/unit/test_context.py::test_context tests/unit/test_context.py::test_context_dict_ignores_keys_except_str tests/unit/test_context.py::test_merge_from_raises_if_file_not_exist tests/func/test_stage_resolver.py::test_vars tests/unit/test_context.py::test_track_from_multiple_files tests/unit/test_context.py::test_node_value tests/func/test_stage_resolver.py::test_foreach_loop_dict tests/unit/test_context.py::test_loop_context 'tests/func/test_stage_resolver.py::test_coll[coll1]' tests/unit/test_context.py::test_overwrite_with_setitem tests/unit/test_context.py::test_merge_dict tests/func/test_stage_resolver.py::test_simple_foreach_loop tests/unit/test_context.py::test_load_from tests/func/test_stage_resolver.py::test_set_with_foreach tests/func/test_stage_resolver.py::test_no_params_yaml_and_vars tests/unit/test_context.py::test_clone 'tests/func/test_stage_resolver.py::test_coll[coll0]' tests/unit/test_context.py::test_resolve_resolves_dict_keys tests/unit/test_context.py::test_repr tests/unit/test_context.py::test_context_setitem_getitem 'tests/func/test_stage_resolver.py::test_set[3]'
: '>>>>> End Test Output'
git checkout 7c45711e34f565330be416621037f983d0034bef -- tests/func/test_stage_resolver.py tests/unit/test_context.py 2>/dev/null || true
