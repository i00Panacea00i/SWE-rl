#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 37761a2627c1e41c35c03e55cd5284d2f4f1386d -- tests/func/test_data_cloud.py tests/unit/command/test_data_sync.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_data_cloud.py b/tests/func/test_data_cloud.py
--- a/tests/func/test_data_cloud.py
+++ b/tests/func/test_data_cloud.py
@@ -7,6 +7,7 @@
 
 import dvc_data
 from dvc.cli import main
+from dvc.exceptions import CheckoutError
 from dvc.external_repo import clean_repos
 from dvc.stage.exceptions import StageNotFound
 from dvc.testing.remote_tests import TestRemote  # noqa, pylint: disable=unused-import
@@ -561,3 +562,17 @@ def test_target_remote(tmp_dir, dvc, make_remote):
         "6b18131dc289fd37006705affe961ef8.dir",
         "b8a9f715dbb64fd5c56e7783c6820a61",
     }
+
+
+def test_pull_allow_missing(tmp_dir, dvc, local_remote):
+    dvc.stage.add(name="bar", outs=["bar"], cmd="echo bar > bar")
+
+    with pytest.raises(CheckoutError):
+        dvc.pull()
+
+    tmp_dir.dvc_gen("foo", "foo")
+    dvc.push()
+    clean(["foo"], dvc)
+
+    stats = dvc.pull(allow_missing=True)
+    assert stats["fetched"] == 1
diff --git a/tests/unit/command/test_data_sync.py b/tests/unit/command/test_data_sync.py
--- a/tests/unit/command/test_data_sync.py
+++ b/tests/unit/command/test_data_sync.py
@@ -58,6 +58,7 @@ def test_pull(mocker):
             "--recursive",
             "--run-cache",
             "--glob",
+            "--allow-missing",
         ]
     )
     assert cli_args.func == CmdDataPull
@@ -79,6 +80,7 @@ def test_pull(mocker):
         recursive=True,
         run_cache=True,
         glob=True,
+        allow_missing=True,
     )
 
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail tests/unit/command/test_data_sync.py::test_pull tests/func/test_data_cloud.py::test_pull_allow_missing 'tests/func/test_data_cloud.py::test_push_stats[fs0-2' tests/func/test_data_cloud.py::test_target_remote tests/func/test_data_cloud.py::test_hash_recalculation tests/func/test_data_cloud.py::test_warn_on_outdated_stage tests/func/test_data_cloud.py::test_push_pull_fetch_pipeline_stages tests/func/test_data_cloud.py::test_pull_partial tests/func/test_data_cloud.py::test_dvc_pull_pipeline_stages 'tests/func/test_data_cloud.py::test_fetch_stats[fs2-Everything' 'tests/func/test_data_cloud.py::test_fetch_stats[fs0-2' tests/unit/command/test_data_sync.py::test_fetch tests/func/test_data_cloud.py::TestRemote::test tests/unit/command/test_data_sync.py::test_push 'tests/func/test_data_cloud.py::test_push_stats[fs2-Everything' 'tests/func/test_data_cloud.py::test_push_stats[fs1-1' tests/func/test_data_cloud.py::test_missing_cache 'tests/func/test_data_cloud.py::test_fetch_stats[fs1-1' tests/func/test_data_cloud.py::test_output_remote tests/func/test_data_cloud.py::test_pull_partial_import tests/func/test_data_cloud.py::test_verify_hashes tests/func/test_data_cloud.py::test_cloud_cli tests/func/test_data_cloud.py::test_data_cloud_error_cli tests/func/test_data_cloud.py::test_pull_stats tests/func/test_data_cloud.py::test_pipeline_file_target_ops
: '>>>>> End Test Output'
git checkout 37761a2627c1e41c35c03e55cd5284d2f4f1386d -- tests/func/test_data_cloud.py tests/unit/command/test_data_sync.py 2>/dev/null || true
