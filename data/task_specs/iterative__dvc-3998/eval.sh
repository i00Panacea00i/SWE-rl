#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 5efc3bbee2aeaf9f1e624c583228bc034333fa25 -- tests/unit/command/test_status.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/command/test_status.py b/tests/unit/command/test_status.py
--- a/tests/unit/command/test_status.py
+++ b/tests/unit/command/test_status.py
@@ -1,3 +1,7 @@
+import json
+
+import pytest
+
 from dvc.cli import parse_args
 from dvc.command.status import CmdDataStatus
 
@@ -38,3 +42,34 @@ def test_cloud_status(mocker):
         with_deps=True,
         recursive=True,
     )
+
+
+@pytest.mark.parametrize("status", [{}, {"a": "b", "c": [1, 2, 3]}, [1, 2, 3]])
+def test_status_show_json(mocker, caplog, status):
+    cli_args = parse_args(["status", "--show-json"])
+    assert cli_args.func == CmdDataStatus
+
+    cmd = cli_args.func(cli_args)
+
+    mocker.patch.object(cmd.repo, "status", autospec=True, return_value=status)
+    caplog.clear()
+    assert cmd.run() == 0
+    assert caplog.messages == [json.dumps(status)]
+
+
+@pytest.mark.parametrize(
+    "status, ret", [({}, 0), ({"a": "b", "c": [1, 2, 3]}, 1), ([1, 2, 3], 1)]
+)
+def test_status_quiet(mocker, caplog, capsys, status, ret):
+    cli_args = parse_args(["status", "-q"])
+    assert cli_args.func == CmdDataStatus
+
+    cmd = cli_args.func(cli_args)
+
+    mocker.patch.object(cmd.repo, "status", autospec=True, return_value=status)
+    caplog.clear()
+    assert cmd.run() == ret
+    assert not caplog.messages
+    captured = capsys.readouterr()
+    assert not captured.err
+    assert not captured.out

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/unit/command/test_status.py::test_status_quiet[status0-0]' 'tests/unit/command/test_status.py::test_status_show_json[status1]' 'tests/unit/command/test_status.py::test_status_show_json[status0]' 'tests/unit/command/test_status.py::test_status_show_json[status2]' 'tests/unit/command/test_status.py::test_status_quiet[status2-1]' tests/unit/command/test_status.py::test_cloud_status 'tests/unit/command/test_status.py::test_status_quiet[status1-1]'
: '>>>>> End Test Output'
git checkout 5efc3bbee2aeaf9f1e624c583228bc034333fa25 -- tests/unit/command/test_status.py 2>/dev/null || true
