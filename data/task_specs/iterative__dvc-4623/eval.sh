#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout a664059eff27632a34e58ca8ca08be8bfa117f7e -- tests/unit/remote/ssh/test_ssh.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/remote/ssh/test_ssh.py b/tests/unit/remote/ssh/test_ssh.py
--- a/tests/unit/remote/ssh/test_ssh.py
+++ b/tests/unit/remote/ssh/test_ssh.py
@@ -183,6 +183,31 @@ def test_ssh_gss_auth(mock_file, mock_exists, dvc, config, expected_gss_auth):
     assert tree.gss_auth == expected_gss_auth
 
 
+@pytest.mark.parametrize(
+    "config,expected_allow_agent",
+    [
+        ({"url": "ssh://example.com"}, True),
+        ({"url": "ssh://not_in_ssh_config.com"}, True),
+        ({"url": "ssh://example.com", "allow_agent": True}, True),
+        ({"url": "ssh://example.com", "allow_agent": False}, False),
+    ],
+)
+@patch("os.path.exists", return_value=True)
+@patch(
+    f"{builtin_module_name}.open",
+    new_callable=mock_open,
+    read_data=mock_ssh_config,
+)
+def test_ssh_allow_agent(
+    mock_file, mock_exists, dvc, config, expected_allow_agent
+):
+    tree = SSHTree(dvc, config)
+
+    mock_exists.assert_called_with(SSHTree.ssh_config_filename())
+    mock_file.assert_called_with(SSHTree.ssh_config_filename())
+    assert tree.allow_agent == expected_allow_agent
+
+
 def test_hardlink_optimization(dvc, tmp_dir, ssh):
     tree = SSHTree(dvc, ssh.config)
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/unit/remote/ssh/test_ssh.py::test_ssh_allow_agent[config3-False]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_allow_agent[config0-True]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_allow_agent[config2-True]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_allow_agent[config1-True]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_user[config5-root]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_keyfile[config3-None]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_gss_auth[config1-False]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_host_override_from_config[config1-not_in_ssh_config.com]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_gss_auth[config0-True]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_keyfile[config0-dvc_config.key]' tests/unit/remote/ssh/test_ssh.py::test_url 'tests/unit/remote/ssh/test_ssh.py::test_ssh_host_override_from_config[config0-1.2.3.4]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_keyfile[config1-/root/.ssh/not_default.key]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_port[config2-4321]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_port[config4-2222]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_user[config0-test1]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_gss_auth[config2-False]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_user[config2-ubuntu]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_user[config4-test2]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_port[config5-4321]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_user[config3-test1]' tests/unit/remote/ssh/test_ssh.py::test_no_path 'tests/unit/remote/ssh/test_ssh.py::test_ssh_user[config1-test2]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_port[config3-22]' tests/unit/remote/ssh/test_ssh.py::test_hardlink_optimization 'tests/unit/remote/ssh/test_ssh.py::test_ssh_keyfile[config2-dvc_config.key]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_port[config1-1234]' 'tests/unit/remote/ssh/test_ssh.py::test_ssh_port[config0-2222]'
: '>>>>> End Test Output'
git checkout a664059eff27632a34e58ca8ca08be8bfa117f7e -- tests/unit/remote/ssh/test_ssh.py 2>/dev/null || true
