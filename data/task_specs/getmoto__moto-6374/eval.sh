#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout b180f0a015c625f2fb89a3330176d72b8701c0f9 -- tests/test_ec2/test_flow_logs.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_ec2/test_flow_logs.py b/tests/test_ec2/test_flow_logs.py
--- a/tests/test_ec2/test_flow_logs.py
+++ b/tests/test_ec2/test_flow_logs.py
@@ -68,6 +68,56 @@ def test_create_flow_logs_s3():
     flow_log["MaxAggregationInterval"].should.equal(600)
 
 
+@mock_s3
+@mock_ec2
+def test_create_multiple_flow_logs_s3():
+    s3 = boto3.resource("s3", region_name="us-west-1")
+    client = boto3.client("ec2", region_name="us-west-1")
+
+    vpc = client.create_vpc(CidrBlock="10.0.0.0/16")["Vpc"]
+
+    bucket_name_1 = str(uuid4())
+    bucket_1 = s3.create_bucket(
+        Bucket=bucket_name_1,
+        CreateBucketConfiguration={"LocationConstraint": "us-west-1"},
+    )
+    bucket_name_2 = str(uuid4())
+    bucket_2 = s3.create_bucket(
+        Bucket=bucket_name_2,
+        CreateBucketConfiguration={"LocationConstraint": "us-west-1"},
+    )
+
+    response = client.create_flow_logs(
+        ResourceType="VPC",
+        ResourceIds=[vpc["VpcId"]],
+        TrafficType="ALL",
+        LogDestinationType="s3",
+        LogDestination="arn:aws:s3:::" + bucket_1.name,
+    )["FlowLogIds"]
+    response.should.have.length_of(1)
+
+    response = client.create_flow_logs(
+        ResourceType="VPC",
+        ResourceIds=[vpc["VpcId"]],
+        TrafficType="ALL",
+        LogDestinationType="s3",
+        LogDestination="arn:aws:s3:::" + bucket_2.name,
+    )["FlowLogIds"]
+    response.should.have.length_of(1)
+
+    flow_logs = client.describe_flow_logs(
+        Filters=[{"Name": "resource-id", "Values": [vpc["VpcId"]]}]
+    )["FlowLogs"]
+    flow_logs.should.have.length_of(2)
+
+    flow_log_1 = flow_logs[0]
+    flow_log_2 = flow_logs[1]
+
+    flow_log_1["ResourceId"].should.equal(flow_log_2["ResourceId"])
+    flow_log_1["FlowLogId"].shouldnt.equal(flow_log_2["FlowLogId"])
+    flow_log_1["LogDestination"].shouldnt.equal(flow_log_2["LogDestination"])
+
+
 @mock_logs
 @mock_ec2
 def test_create_flow_logs_cloud_watch():
@@ -127,6 +177,51 @@ def test_create_flow_logs_cloud_watch():
     flow_log["MaxAggregationInterval"].should.equal(600)
 
 
+@mock_logs
+@mock_ec2
+def test_create_multiple_flow_logs_cloud_watch():
+    client = boto3.client("ec2", region_name="us-west-1")
+    logs_client = boto3.client("logs", region_name="us-west-1")
+
+    vpc = client.create_vpc(CidrBlock="10.0.0.0/16")["Vpc"]
+    lg_name_1 = str(uuid4())
+    lg_name_2 = str(uuid4())
+    logs_client.create_log_group(logGroupName=lg_name_1)
+    logs_client.create_log_group(logGroupName=lg_name_2)
+
+    response = client.create_flow_logs(
+        ResourceType="VPC",
+        ResourceIds=[vpc["VpcId"]],
+        TrafficType="ALL",
+        LogDestinationType="cloud-watch-logs",
+        LogGroupName=lg_name_1,
+        DeliverLogsPermissionArn="arn:aws:iam::" + ACCOUNT_ID + ":role/test-role",
+    )["FlowLogIds"]
+    response.should.have.length_of(1)
+
+    response = client.create_flow_logs(
+        ResourceType="VPC",
+        ResourceIds=[vpc["VpcId"]],
+        TrafficType="ALL",
+        LogDestinationType="cloud-watch-logs",
+        LogGroupName=lg_name_2,
+        DeliverLogsPermissionArn="arn:aws:iam::" + ACCOUNT_ID + ":role/test-role",
+    )["FlowLogIds"]
+    response.should.have.length_of(1)
+
+    flow_logs = client.describe_flow_logs(
+        Filters=[{"Name": "resource-id", "Values": [vpc["VpcId"]]}]
+    )["FlowLogs"]
+    flow_logs.should.have.length_of(2)
+
+    flow_log_1 = flow_logs[0]
+    flow_log_2 = flow_logs[1]
+
+    flow_log_1["ResourceId"].should.equal(flow_log_2["ResourceId"])
+    flow_log_1["FlowLogId"].shouldnt.equal(flow_log_2["FlowLogId"])
+    flow_log_1["LogGroupName"].shouldnt.equal(flow_log_2["LogGroupName"])
+
+
 @mock_s3
 @mock_ec2
 def test_create_flow_log_create():

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_ec2/test_flow_logs.py::test_create_multiple_flow_logs_s3 tests/test_ec2/test_flow_logs.py::test_create_multiple_flow_logs_cloud_watch tests/test_ec2/test_flow_logs.py::test_create_flow_logs_cloud_watch tests/test_ec2/test_flow_logs.py::test_describe_flow_logs_filtering tests/test_ec2/test_flow_logs.py::test_delete_flow_logs_non_existing tests/test_ec2/test_flow_logs.py::test_delete_flow_logs tests/test_ec2/test_flow_logs.py::test_create_flow_logs_s3 tests/test_ec2/test_flow_logs.py::test_delete_flow_logs_delete_many tests/test_ec2/test_flow_logs.py::test_create_flow_logs_invalid_parameters tests/test_ec2/test_flow_logs.py::test_flow_logs_by_ids tests/test_ec2/test_flow_logs.py::test_create_flow_logs_unsuccessful tests/test_ec2/test_flow_logs.py::test_create_flow_log_create
: '>>>>> End Test Output'
git checkout b180f0a015c625f2fb89a3330176d72b8701c0f9 -- tests/test_ec2/test_flow_logs.py 2>/dev/null || true
