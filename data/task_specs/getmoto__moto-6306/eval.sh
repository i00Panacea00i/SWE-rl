#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 52846c9555a3077b11a391fbfcd619d0d6e776f6 -- tests/test_rds/test_rds_export_tasks.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_rds/test_rds_export_tasks.py b/tests/test_rds/test_rds_export_tasks.py
--- a/tests/test_rds/test_rds_export_tasks.py
+++ b/tests/test_rds/test_rds_export_tasks.py
@@ -25,6 +25,30 @@ def _prepare_db_snapshot(client, snapshot_name="snapshot-1"):
     return resp["DBSnapshot"]["DBSnapshotArn"]
 
 
+def _prepare_db_cluster_snapshot(client, snapshot_name="cluster-snapshot-1"):
+    db_cluster_identifier = "db-cluster-primary-1"
+    client.create_db_cluster(
+        AvailabilityZones=[
+            "us-west-2",
+        ],
+        BackupRetentionPeriod=1,
+        DBClusterIdentifier=db_cluster_identifier,
+        DBClusterParameterGroupName="db-cluster-primary-1-group",
+        DatabaseName="staging-postgres",
+        Engine="postgres",
+        EngineVersion="5.6.10a",
+        MasterUserPassword="hunterxhunder",
+        MasterUsername="root",
+        Port=3306,
+        StorageEncrypted=True,
+    )
+    resp = client.create_db_cluster_snapshot(
+        DBClusterSnapshotIdentifier=snapshot_name,
+        DBClusterIdentifier=db_cluster_identifier,
+    )
+    return resp["DBClusterSnapshot"]["DBClusterSnapshotArn"]
+
+
 @mock_rds
 def test_start_export_task_fails_unknown_snapshot():
     client = boto3.client("rds", region_name="us-west-2")
@@ -44,7 +68,7 @@ def test_start_export_task_fails_unknown_snapshot():
 
 
 @mock_rds
-def test_start_export_task():
+def test_start_export_task_db():
     client = boto3.client("rds", region_name="us-west-2")
     source_arn = _prepare_db_snapshot(client)
 
@@ -67,6 +91,34 @@ def test_start_export_task():
         "arn:aws:kms:::key/0ea3fef3-80a7-4778-9d8c-1c0c6EXAMPLE"
     )
     export["ExportOnly"].should.equal(["schema.table"])
+    export["SourceType"].should.equal("SNAPSHOT")
+
+
+@mock_rds
+def test_start_export_task_db_cluster():
+    client = boto3.client("rds", region_name="us-west-2")
+    source_arn = _prepare_db_cluster_snapshot(client)
+
+    export = client.start_export_task(
+        ExportTaskIdentifier="export-snapshot-1",
+        SourceArn=source_arn,
+        S3BucketName="export-bucket",
+        S3Prefix="snaps/",
+        IamRoleArn="arn:aws:iam:::role/export-role",
+        KmsKeyId="arn:aws:kms:::key/0ea3fef3-80a7-4778-9d8c-1c0c6EXAMPLE",
+        ExportOnly=["schema.table"],
+    )
+
+    export["ExportTaskIdentifier"].should.equal("export-snapshot-1")
+    export["SourceArn"].should.equal(source_arn)
+    export["S3Bucket"].should.equal("export-bucket")
+    export["S3Prefix"].should.equal("snaps/")
+    export["IamRoleArn"].should.equal("arn:aws:iam:::role/export-role")
+    export["KmsKeyId"].should.equal(
+        "arn:aws:kms:::key/0ea3fef3-80a7-4778-9d8c-1c0c6EXAMPLE"
+    )
+    export["ExportOnly"].should.equal(["schema.table"])
+    export["SourceType"].should.equal("CLUSTER")
 
 
 @mock_rds

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_rds/test_rds_export_tasks.py::test_start_export_task_db_cluster tests/test_rds/test_rds_export_tasks.py::test_start_export_task_db tests/test_rds/test_rds_export_tasks.py::test_describe_export_tasks_fails_unknown_task tests/test_rds/test_rds_export_tasks.py::test_cancel_export_task_fails_unknown_task tests/test_rds/test_rds_export_tasks.py::test_start_export_task_fails_unknown_snapshot tests/test_rds/test_rds_export_tasks.py::test_cancel_export_task tests/test_rds/test_rds_export_tasks.py::test_describe_export_tasks tests/test_rds/test_rds_export_tasks.py::test_start_export_task_fail_already_exists
: '>>>>> End Test Output'
git checkout 52846c9555a3077b11a391fbfcd619d0d6e776f6 -- tests/test_rds/test_rds_export_tasks.py 2>/dev/null || true
