#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout d10a8e9900bedf298dbf380d74172e3481aff828 -- tests/test_awslambda/test_lambda.py tests/test_awslambda/test_lambda_policy.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_awslambda/test_lambda.py b/tests/test_awslambda/test_lambda.py
--- a/tests/test_awslambda/test_lambda.py
+++ b/tests/test_awslambda/test_lambda.py
@@ -18,7 +18,9 @@
     get_role_name,
     get_test_zip_file1,
     get_test_zip_file2,
+    get_test_zip_file3,
     create_invalid_lambda,
+    _process_lambda,
 )
 
 _lambda_region = "us-west-2"
@@ -870,6 +872,7 @@ def test_list_versions_by_function():
         MemorySize=128,
         Publish=True,
     )
+    conn.update_function_code(FunctionName=function_name, ZipFile=get_test_zip_file1())
 
     res = conn.publish_version(FunctionName=function_name)
     assert res["ResponseMetadata"]["HTTPStatusCode"] == 201
@@ -1041,12 +1044,14 @@ def test_update_function_zip(key):
         Publish=True,
     )
     name_or_arn = fxn[key]
+    first_sha = fxn["CodeSha256"]
 
     zip_content_two = get_test_zip_file2()
 
-    conn.update_function_code(
+    update1 = conn.update_function_code(
         FunctionName=name_or_arn, ZipFile=zip_content_two, Publish=True
     )
+    update1["CodeSha256"].shouldnt.equal(first_sha)
 
     response = conn.get_function(FunctionName=function_name, Qualifier="2")
 
@@ -1066,6 +1071,30 @@ def test_update_function_zip(key):
     config.should.have.key("FunctionName").equals(function_name)
     config.should.have.key("Version").equals("2")
     config.should.have.key("LastUpdateStatus").equals("Successful")
+    config.should.have.key("CodeSha256").equals(update1["CodeSha256"])
+
+    most_recent_config = conn.get_function(FunctionName=function_name)
+    most_recent_config["Configuration"]["CodeSha256"].should.equal(
+        update1["CodeSha256"]
+    )
+
+    # Publishing this again, with the same code, gives us the same version
+    same_update = conn.update_function_code(
+        FunctionName=name_or_arn, ZipFile=zip_content_two, Publish=True
+    )
+    same_update["FunctionArn"].should.equal(
+        most_recent_config["Configuration"]["FunctionArn"] + ":2"
+    )
+    same_update["Version"].should.equal("2")
+
+    # Only when updating the code should we have a new version
+    new_update = conn.update_function_code(
+        FunctionName=name_or_arn, ZipFile=get_test_zip_file3(), Publish=True
+    )
+    new_update["FunctionArn"].should.equal(
+        most_recent_config["Configuration"]["FunctionArn"] + ":3"
+    )
+    new_update["Version"].should.equal("3")
 
 
 @mock_lambda
@@ -1191,6 +1220,8 @@ def test_multiple_qualifiers():
     )
 
     for _ in range(10):
+        new_zip = _process_lambda(f"func content {_}")
+        client.update_function_code(FunctionName=fn_name, ZipFile=new_zip)
         client.publish_version(FunctionName=fn_name)
 
     resp = client.list_versions_by_function(FunctionName=fn_name)["Versions"]
diff --git a/tests/test_awslambda/test_lambda_policy.py b/tests/test_awslambda/test_lambda_policy.py
--- a/tests/test_awslambda/test_lambda_policy.py
+++ b/tests/test_awslambda/test_lambda_policy.py
@@ -7,7 +7,7 @@
 from moto import mock_lambda, mock_s3
 from moto.core import DEFAULT_ACCOUNT_ID as ACCOUNT_ID
 from uuid import uuid4
-from .utilities import get_role_name, get_test_zip_file1
+from .utilities import get_role_name, get_test_zip_file1, get_test_zip_file2
 
 _lambda_region = "us-west-2"
 boto3.setup_default_session(region_name=_lambda_region)
@@ -139,7 +139,7 @@ def test_get_policy_with_qualifier():
         Publish=True,
     )
 
-    zip_content_two = get_test_zip_file1()
+    zip_content_two = get_test_zip_file2()
 
     conn.update_function_code(
         FunctionName=function_name, ZipFile=zip_content_two, Publish=True
@@ -250,7 +250,7 @@ def test_remove_function_permission__with_qualifier(key):
     name_or_arn = f[key]
 
     # Ensure Qualifier=2 exists
-    zip_content_two = get_test_zip_file1()
+    zip_content_two = get_test_zip_file2()
     conn.update_function_code(
         FunctionName=function_name, ZipFile=zip_content_two, Publish=True
     )

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/test_awslambda/test_lambda.py::test_update_function_zip[FunctionName]' 'tests/test_awslambda/test_lambda.py::test_update_function_zip[FunctionArn]' 'tests/test_awslambda/test_lambda.py::test_publish_version_unknown_function[bad_function_name]' tests/test_awslambda/test_lambda.py::test_create_function_from_zipfile tests/test_awslambda/test_lambda.py::test_create_function_with_already_exists 'tests/test_awslambda/test_lambda.py::test_get_function_configuration[FunctionArn]' tests/test_awslambda/test_lambda.py::test_delete_function_by_arn 'tests/test_awslambda/test_lambda.py::test_update_configuration[FunctionArn]' 'tests/test_awslambda/test_lambda.py::test_publish_version_unknown_function[arn:aws:lambda:eu-west-1:123456789012:function:bad_function_name]' tests/test_awslambda/test_lambda_policy.py::test_add_permission_with_principalorgid 'tests/test_awslambda/test_lambda.py::test_lambda_regions[us-west-2]' tests/test_awslambda/test_lambda_policy.py::test_get_unknown_policy 'tests/test_awslambda/test_lambda_policy.py::test_add_function_permission[FunctionArn]' tests/test_awslambda/test_lambda.py::test_get_function_by_arn 'tests/test_awslambda/test_lambda.py::test_get_function_code_signing_config[FunctionName]' tests/test_awslambda/test_lambda.py::test_create_function_from_stubbed_ecr 'tests/test_awslambda/test_lambda.py::test_get_function_code_signing_config[FunctionArn]' tests/test_awslambda/test_lambda.py::test_update_function_s3 tests/test_awslambda/test_lambda.py::test_list_versions_by_function_for_nonexistent_function 'tests/test_awslambda/test_lambda.py::test_create_function__with_tracingmode[tracing_mode0]' 'tests/test_awslambda/test_lambda.py::test_create_function__with_tracingmode[tracing_mode2]' tests/test_awslambda/test_lambda.py::test_create_function_with_arn_from_different_account 'tests/test_awslambda/test_lambda.py::test_create_function__with_tracingmode[tracing_mode1]' 'tests/test_awslambda/test_lambda_policy.py::test_remove_function_permission__with_qualifier[FunctionName]' tests/test_awslambda/test_lambda.py::test_remove_unknown_permission_throws_error tests/test_awslambda/test_lambda.py::test_multiple_qualifiers 'tests/test_awslambda/test_lambda_policy.py::test_remove_function_permission__with_qualifier[FunctionArn]' tests/test_awslambda/test_lambda.py::test_get_role_name_utility_race_condition tests/test_awslambda/test_lambda.py::test_list_functions 'tests/test_awslambda/test_lambda_policy.py::test_get_function_policy[FunctionArn]' tests/test_awslambda/test_lambda.py::test_get_function 'tests/test_awslambda/test_lambda.py::test_update_configuration[FunctionName]' tests/test_awslambda/test_lambda.py::test_create_function_from_aws_bucket 'tests/test_awslambda/test_lambda.py::test_get_function_configuration[FunctionName]' 'tests/test_awslambda/test_lambda.py::test_lambda_regions[cn-northwest-1]' 'tests/test_awslambda/test_lambda_policy.py::test_remove_function_permission[FunctionArn]' tests/test_awslambda/test_lambda.py::test_create_function_with_unknown_arn tests/test_awslambda/test_lambda.py::test_delete_unknown_function 'tests/test_awslambda/test_lambda_policy.py::test_get_function_policy[FunctionName]' tests/test_awslambda/test_lambda.py::test_list_versions_by_function tests/test_awslambda/test_lambda.py::test_list_create_list_get_delete_list tests/test_awslambda/test_lambda.py::test_create_based_on_s3_with_missing_bucket tests/test_awslambda/test_lambda.py::test_create_function_with_invalid_arn tests/test_awslambda/test_lambda.py::test_publish tests/test_awslambda/test_lambda_policy.py::test_get_policy_with_qualifier tests/test_awslambda/test_lambda.py::test_create_function_from_mocked_ecr_image 'tests/test_awslambda/test_lambda_policy.py::test_remove_function_permission[FunctionName]' tests/test_awslambda/test_lambda.py::test_get_function_created_with_zipfile tests/test_awslambda/test_lambda.py::test_create_function_from_mocked_ecr_missing_image 'tests/test_awslambda/test_lambda_policy.py::test_add_function_permission[FunctionName]' tests/test_awslambda/test_lambda.py::test_delete_function tests/test_awslambda/test_lambda_policy.py::test_add_permission_with_unknown_qualifier
: '>>>>> End Test Output'
git checkout d10a8e9900bedf298dbf380d74172e3481aff828 -- tests/test_awslambda/test_lambda.py tests/test_awslambda/test_lambda_policy.py 2>/dev/null || true
