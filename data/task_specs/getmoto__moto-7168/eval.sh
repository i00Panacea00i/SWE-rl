#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e5f962193cb12e696bd6ec641844c4d09b5fb87c -- tests/test_scheduler/test_scheduler.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_scheduler/test_scheduler.py b/tests/test_scheduler/test_scheduler.py
--- a/tests/test_scheduler/test_scheduler.py
+++ b/tests/test_scheduler/test_scheduler.py
@@ -175,6 +175,17 @@ def test_get_schedule_for_unknown_group():
     assert err["Code"] == "ResourceNotFoundException"
 
 
+@mock_scheduler
+def test_get_schedule_for_none_existing_schedule():
+    client = boto3.client("scheduler", region_name="eu-west-1")
+
+    with pytest.raises(ClientError) as exc:
+        client.get_schedule(Name="my-schedule")
+    err = exc.value.response["Error"]
+    assert err["Code"] == "ResourceNotFoundException"
+    assert err["Message"] == "Schedule my-schedule does not exist."
+
+
 @mock_scheduler
 def test_list_schedules():
     client = boto3.client("scheduler", region_name="eu-west-1")
@@ -206,3 +217,14 @@ def test_list_schedules():
 
     schedules = client.list_schedules(State="ENABLED")["Schedules"]
     assert len(schedules) == 4
+
+
+@mock_scheduler
+def test_delete_schedule_for_none_existing_schedule():
+    client = boto3.client("scheduler", region_name="eu-west-1")
+
+    with pytest.raises(ClientError) as exc:
+        client.delete_schedule(Name="my-schedule")
+    err = exc.value.response["Error"]
+    assert err["Code"] == "ResourceNotFoundException"
+    assert err["Message"] == "Schedule my-schedule does not exist."

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_scheduler/test_scheduler.py::test_get_schedule_for_none_existing_schedule tests/test_scheduler/test_scheduler.py::test_delete_schedule_for_none_existing_schedule tests/test_scheduler/test_scheduler.py::test_list_schedules tests/test_scheduler/test_scheduler.py::test_create_get_schedule tests/test_scheduler/test_scheduler.py::test_create_duplicate_schedule tests/test_scheduler/test_scheduler.py::test_create_get_delete__in_different_group 'tests/test_scheduler/test_scheduler.py::test_update_schedule[with_group]' tests/test_scheduler/test_scheduler.py::test_get_schedule_for_unknown_group 'tests/test_scheduler/test_scheduler.py::test_update_schedule[without_group]'
: '>>>>> End Test Output'
git checkout e5f962193cb12e696bd6ec641844c4d09b5fb87c -- tests/test_scheduler/test_scheduler.py 2>/dev/null || true
