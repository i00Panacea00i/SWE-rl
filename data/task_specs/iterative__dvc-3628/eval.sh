#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8455b7bece300d93a4f50e130f83b1c4ec373efa -- tests/func/test_config.py tests/func/test_remote.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_config.py b/tests/func/test_config.py
--- a/tests/func/test_config.py
+++ b/tests/func/test_config.py
@@ -94,6 +94,12 @@ def test_merging_two_levels(dvc):
     with dvc.config.edit() as conf:
         conf["remote"]["test"] = {"url": "ssh://example.com"}
 
+    with pytest.raises(
+        ConfigError, match=r"expected 'url' for dictionary value"
+    ):
+        with dvc.config.edit("global") as conf:
+            conf["remote"]["test"] = {"password": "1"}
+
     with dvc.config.edit("local") as conf:
         conf["remote"]["test"] = {"password": "1"}
 
diff --git a/tests/func/test_remote.py b/tests/func/test_remote.py
--- a/tests/func/test_remote.py
+++ b/tests/func/test_remote.py
@@ -254,3 +254,19 @@ def test_push_order(tmp_dir, dvc, tmp_path_factory, mocker):
     dvc.push()
     # last uploaded file should be dir checksum
     assert mocked_upload.call_args[0][0].endswith(".dir")
+
+
+def test_remote_modify_validation(dvc):
+    remote_name = "drive"
+    unsupported_config = "unsupported_config"
+    assert (
+        main(["remote", "add", "-d", remote_name, "gdrive://test/test"]) == 0
+    )
+    assert (
+        main(
+            ["remote", "modify", remote_name, unsupported_config, "something"]
+        )
+        == 251
+    )
+    config = configobj.ConfigObj(dvc.config.files["repo"])
+    assert unsupported_config not in config['remote "{}"'.format(remote_name)]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_remote.py::TestRemote::test_relative_path tests/func/test_remote.py::TestRemoteDefault::test tests/func/test_config.py::test_config_loads_without_error_for_non_dvc_repo tests/func/test_remote.py::TestRemote::test_referencing_other_remotes tests/func/test_remote.py::TestRemote::test_overwrite tests/func/test_config.py::test_merging_two_levels tests/func/test_remote.py::TestRemote::test tests/func/test_remote.py::TestRemoteRemove::test tests/func/test_config.py::TestConfigCLI::test_non_existing tests/func/test_config.py::TestConfigCLI::test tests/func/test_config.py::TestConfigCLI::test_root tests/func/test_config.py::TestConfigCLI::test_local tests/func/test_config.py::test_set_invalid_key
: '>>>>> End Test Output'
git checkout 8455b7bece300d93a4f50e130f83b1c4ec373efa -- tests/func/test_config.py tests/func/test_remote.py 2>/dev/null || true
