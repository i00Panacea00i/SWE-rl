#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 6d783b8d97fa29387d064d7340bbc610afaf6938 -- tests/func/test_repro_multistage.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_repro_multistage.py b/tests/func/test_repro_multistage.py
--- a/tests/func/test_repro_multistage.py
+++ b/tests/func/test_repro_multistage.py
@@ -9,6 +9,7 @@
 from dvc.dvcfile import LOCK_FILE, PROJECT_FILE
 from dvc.exceptions import CyclicGraphError, ReproductionError
 from dvc.stage import PipelineStage
+from dvc.stage.cache import RunCacheNotSupported
 from dvc.stage.exceptions import StageNotFound
 from dvc.utils.fs import remove
 
@@ -457,3 +458,30 @@ def test_repro_allow_missing_and_pull(tmp_dir, dvc, mocker, local_remote):
     ret = dvc.reproduce(pull=True, allow_missing=True)
     # create-foo is skipped ; copy-foo pulls missing dep
     assert len(ret) == 1
+
+
+def test_repro_pulls_continue_without_run_cache(tmp_dir, dvc, mocker, local_remote):
+    (foo,) = tmp_dir.dvc_gen("foo", "foo")
+
+    dvc.push()
+    mocker.patch.object(
+        dvc.stage_cache, "pull", side_effect=RunCacheNotSupported("foo")
+    )
+    dvc.stage.add(name="copy-foo", cmd="cp foo bar", deps=["foo"], outs=["bar"])
+    remove("foo")
+    remove(foo.outs[0].cache_path)
+
+    assert dvc.reproduce(pull=True)
+
+
+def test_repro_skip_pull_if_no_run_cache_is_passed(tmp_dir, dvc, mocker, local_remote):
+    (foo,) = tmp_dir.dvc_gen("foo", "foo")
+
+    dvc.push()
+    spy_pull = mocker.spy(dvc.stage_cache, "pull")
+    dvc.stage.add(name="copy-foo", cmd="cp foo bar", deps=["foo"], outs=["bar"])
+    remove("foo")
+    remove(foo.outs[0].cache_path)
+
+    assert dvc.reproduce(pull=True, run_cache=False)
+    assert not spy_pull.called

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_repro_multistage.py::test_repro_pulls_continue_without_run_cache tests/func/test_repro_multistage.py::test_repro_skip_pull_if_no_run_cache_is_passed tests/func/test_repro_multistage.py::test_repro_when_new_out_overlaps_others_stage_outs tests/func/test_repro_multistage.py::test_repro_frozen 'tests/func/test_repro_multistage.py::test_repro_list_of_commands_in_order[True]' 'tests/func/test_repro_multistage.py::test_repro_list_of_commands_raise_and_stops_after_failure[True]' tests/func/test_repro_multistage.py::test_downstream tests/func/test_repro_multistage.py::test_repro_allow_missing_and_pull tests/func/test_repro_multistage.py::test_repro_when_new_outs_added_does_not_exist tests/func/test_repro_multistage.py::test_repro_when_new_deps_is_moved 'tests/func/test_repro_multistage.py::test_repro_list_of_commands_raise_and_stops_after_failure[False]' tests/func/test_repro_multistage.py::test_repro_when_lockfile_gets_deleted tests/func/test_repro_multistage.py::test_repro_when_new_deps_added_does_not_exist tests/func/test_repro_multistage.py::test_repro_when_new_outs_is_added_in_dvcfile 'tests/func/test_repro_multistage.py::test_repro_list_of_commands_in_order[False]' tests/func/test_repro_multistage.py::test_repro_allow_missing tests/func/test_repro_multistage.py::test_non_existing_stage_name tests/func/test_repro_multistage.py::test_cyclic_graph_error tests/func/test_repro_multistage.py::test_repro_when_cmd_changes tests/func/test_repro_multistage.py::test_repro_multiple_params tests/func/test_repro_multistage.py::test_repro_pulls_mising_data_source tests/func/test_repro_multistage.py::test_repro_when_new_deps_is_added_in_dvcfile
: '>>>>> End Test Output'
git checkout 6d783b8d97fa29387d064d7340bbc610afaf6938 -- tests/func/test_repro_multistage.py 2>/dev/null || true
