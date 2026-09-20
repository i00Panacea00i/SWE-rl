#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout db862bcf3b5ea051d412620caccbc08d72c8f441 -- tests/test_kinesis/test_kinesis.py tests/test_kinesis/test_server.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_kinesis/test_kinesis.py b/tests/test_kinesis/test_kinesis.py
--- a/tests/test_kinesis/test_kinesis.py
+++ b/tests/test_kinesis/test_kinesis.py
@@ -137,6 +137,26 @@ def test_describe_stream_summary():
     assert stream["StreamName"] == stream_name
 
 
+@mock_aws
+def test_list_streams_stream_discription():
+    conn = boto3.client("kinesis", region_name="us-west-2")
+
+    for i in range(3):
+        conn.create_stream(StreamName=f"stream{i}", ShardCount=i+1)
+
+    resp = conn.list_streams()
+    assert len(resp["StreamSummaries"]) == 3
+    for i, stream in enumerate(resp["StreamSummaries"]):
+        stream_name = f"stream{i}"
+        assert stream["StreamName"] == stream_name
+        assert (
+            stream["StreamARN"]
+            == f"arn:aws:kinesis:us-west-2:{ACCOUNT_ID}:stream/{stream_name}"
+        )
+        assert stream["StreamStatus"] == "ACTIVE"
+        assert stream.get("StreamCreationTimestamp")
+
+
 @mock_aws
 def test_basic_shard_iterator():
     client = boto3.client("kinesis", region_name="us-west-1")
diff --git a/tests/test_kinesis/test_server.py b/tests/test_kinesis/test_server.py
--- a/tests/test_kinesis/test_server.py
+++ b/tests/test_kinesis/test_server.py
@@ -12,4 +12,8 @@ def test_list_streams():
     res = test_client.get("/?Action=ListStreams")
 
     json_data = json.loads(res.data.decode("utf-8"))
-    assert json_data == {"HasMoreStreams": False, "StreamNames": []}
+    assert json_data == {
+        "HasMoreStreams": False,
+        "StreamNames": [],
+        "StreamSummaries": []
+    }

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_kinesis/test_kinesis.py::test_list_streams_stream_discription tests/test_kinesis/test_server.py::test_list_streams tests/test_kinesis/test_kinesis.py::test_get_records_timestamp_filtering tests/test_kinesis/test_kinesis.py::test_describe_stream_summary tests/test_kinesis/test_kinesis.py::test_add_list_remove_tags tests/test_kinesis/test_kinesis.py::test_get_records_at_very_old_timestamp tests/test_kinesis/test_kinesis.py::test_basic_shard_iterator_by_stream_arn tests/test_kinesis/test_kinesis.py::test_invalid_increase_stream_retention_too_low tests/test_kinesis/test_kinesis.py::test_valid_increase_stream_retention_period tests/test_kinesis/test_kinesis.py::test_decrease_stream_retention_period_too_low tests/test_kinesis/test_kinesis.py::test_update_stream_mode tests/test_kinesis/test_kinesis.py::test_valid_decrease_stream_retention_period tests/test_kinesis/test_kinesis.py::test_stream_creation_on_demand tests/test_kinesis/test_kinesis.py::test_get_records_limit tests/test_kinesis/test_kinesis.py::test_decrease_stream_retention_period_upwards tests/test_kinesis/test_kinesis.py::test_decrease_stream_retention_period_too_high tests/test_kinesis/test_kinesis.py::test_delete_unknown_stream tests/test_kinesis/test_kinesis.py::test_get_records_at_timestamp tests/test_kinesis/test_kinesis.py::test_invalid_increase_stream_retention_too_high tests/test_kinesis/test_kinesis.py::test_invalid_shard_iterator_type tests/test_kinesis/test_kinesis.py::test_get_records_after_sequence_number tests/test_kinesis/test_kinesis.py::test_get_records_at_sequence_number tests/test_kinesis/test_kinesis.py::test_invalid_increase_stream_retention_period tests/test_kinesis/test_kinesis.py::test_get_records_millis_behind_latest tests/test_kinesis/test_kinesis.py::test_basic_shard_iterator tests/test_kinesis/test_kinesis.py::test_merge_shards_invalid_arg tests/test_kinesis/test_kinesis.py::test_merge_shards tests/test_kinesis/test_kinesis.py::test_get_records_at_very_new_timestamp tests/test_kinesis/test_kinesis.py::test_list_and_delete_stream tests/test_kinesis/test_kinesis.py::test_get_records_from_empty_stream_at_timestamp tests/test_kinesis/test_kinesis.py::test_get_records_latest tests/test_kinesis/test_kinesis.py::test_put_records tests/test_kinesis/test_kinesis.py::test_describe_non_existent_stream tests/test_kinesis/test_kinesis.py::test_list_many_streams tests/test_kinesis/test_kinesis.py::test_get_invalid_shard_iterator
: '>>>>> End Test Output'
git checkout db862bcf3b5ea051d412620caccbc08d72c8f441 -- tests/test_kinesis/test_kinesis.py tests/test_kinesis/test_server.py 2>/dev/null || true
