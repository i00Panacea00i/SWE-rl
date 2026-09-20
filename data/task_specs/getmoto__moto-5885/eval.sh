#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 67197cb8a566ee5d598905f836c90de8ee9399e1 -- tests/test_eks/test_eks_ec2.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_eks/test_eks_ec2.py b/tests/test_eks/test_eks_ec2.py
new file mode 100644
--- /dev/null
+++ b/tests/test_eks/test_eks_ec2.py
@@ -0,0 +1,73 @@
+import boto3
+
+from moto import mock_ec2, mock_eks
+from .test_eks_constants import NODEROLE_ARN_VALUE, SUBNET_IDS
+
+
+@mock_eks
+def test_passing_an_unknown_launchtemplate_is_supported():
+    eks = boto3.client("eks", "us-east-2")
+    eks.create_cluster(name="a", roleArn=NODEROLE_ARN_VALUE, resourcesVpcConfig={})
+    group = eks.create_nodegroup(
+        clusterName="a",
+        nodegroupName="b",
+        launchTemplate={"name": "random"},
+        nodeRole=NODEROLE_ARN_VALUE,
+        subnets=SUBNET_IDS,
+    )["nodegroup"]
+
+    group["launchTemplate"].should.equal({"name": "random"})
+
+
+@mock_ec2
+@mock_eks
+def test_passing_a_known_launchtemplate_by_name():
+    ec2 = boto3.client("ec2", region_name="us-east-2")
+    eks = boto3.client("eks", "us-east-2")
+
+    lt_id = ec2.create_launch_template(
+        LaunchTemplateName="ltn",
+        LaunchTemplateData={
+            "TagSpecifications": [
+                {"ResourceType": "instance", "Tags": [{"Key": "t", "Value": "v"}]}
+            ]
+        },
+    )["LaunchTemplate"]["LaunchTemplateId"]
+
+    eks.create_cluster(name="a", roleArn=NODEROLE_ARN_VALUE, resourcesVpcConfig={})
+    group = eks.create_nodegroup(
+        clusterName="a",
+        nodegroupName="b",
+        launchTemplate={"name": "ltn"},
+        nodeRole=NODEROLE_ARN_VALUE,
+        subnets=SUBNET_IDS,
+    )["nodegroup"]
+
+    group["launchTemplate"].should.equal({"name": "ltn", "id": lt_id})
+
+
+@mock_ec2
+@mock_eks
+def test_passing_a_known_launchtemplate_by_id():
+    ec2 = boto3.client("ec2", region_name="us-east-2")
+    eks = boto3.client("eks", "us-east-2")
+
+    lt_id = ec2.create_launch_template(
+        LaunchTemplateName="ltn",
+        LaunchTemplateData={
+            "TagSpecifications": [
+                {"ResourceType": "instance", "Tags": [{"Key": "t", "Value": "v"}]}
+            ]
+        },
+    )["LaunchTemplate"]["LaunchTemplateId"]
+
+    eks.create_cluster(name="a", roleArn=NODEROLE_ARN_VALUE, resourcesVpcConfig={})
+    group = eks.create_nodegroup(
+        clusterName="a",
+        nodegroupName="b",
+        launchTemplate={"id": lt_id},
+        nodeRole=NODEROLE_ARN_VALUE,
+        subnets=SUBNET_IDS,
+    )["nodegroup"]
+
+    group["launchTemplate"].should.equal({"name": "ltn", "id": lt_id})

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_eks/test_eks_ec2.py::test_passing_a_known_launchtemplate_by_name tests/test_eks/test_eks_ec2.py::test_passing_a_known_launchtemplate_by_id tests/test_eks/test_eks_ec2.py::test_passing_an_unknown_launchtemplate_is_supported
: '>>>>> End Test Output'
git checkout 67197cb8a566ee5d598905f836c90de8ee9399e1 -- tests/test_eks/test_eks_ec2.py 2>/dev/null || true
