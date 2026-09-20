#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout bb6fb1200f8db61e0d39c9a4da5954469a403fb8 -- tests/test_core/test_decorator_calls.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_core/test_decorator_calls.py b/tests/test_core/test_decorator_calls.py
--- a/tests/test_core/test_decorator_calls.py
+++ b/tests/test_core/test_decorator_calls.py
@@ -109,8 +109,9 @@ def test_no_instance_sent_to_staticmethod(self):
 
 
 @mock_s3
-class TestWithSetup(unittest.TestCase):
+class TestWithSetup_UppercaseU(unittest.TestCase):
     def setUp(self):
+        # This method will be executed automatically, provided we extend the TestCase-class
         s3 = boto3.client("s3", region_name="us-east-1")
         s3.create_bucket(Bucket="mybucket")
 
@@ -124,6 +125,53 @@ def test_should_not_find_unknown_bucket(self):
             s3.head_bucket(Bucket="unknown_bucket")
 
 
+@mock_s3
+class TestWithSetup_LowercaseU:
+    def setup(self, *args):
+        # This method will be executed automatically using pytest
+        s3 = boto3.client("s3", region_name="us-east-1")
+        s3.create_bucket(Bucket="mybucket")
+
+    def test_should_find_bucket(self):
+        s3 = boto3.client("s3", region_name="us-east-1")
+        assert s3.head_bucket(Bucket="mybucket") is not None
+
+    def test_should_not_find_unknown_bucket(self):
+        s3 = boto3.client("s3", region_name="us-east-1")
+        with pytest.raises(ClientError):
+            s3.head_bucket(Bucket="unknown_bucket")
+
+
+@mock_s3
+class TestWithSetupMethod:
+    def setup_method(self, *args):
+        # This method will be executed automatically using pytest
+        s3 = boto3.client("s3", region_name="us-east-1")
+        s3.create_bucket(Bucket="mybucket")
+
+    def test_should_find_bucket(self):
+        s3 = boto3.client("s3", region_name="us-east-1")
+        assert s3.head_bucket(Bucket="mybucket") is not None
+
+    def test_should_not_find_unknown_bucket(self):
+        s3 = boto3.client("s3", region_name="us-east-1")
+        with pytest.raises(ClientError):
+            s3.head_bucket(Bucket="unknown_bucket")
+
+
+@mock_s3
+class TestWithInvalidSetupMethod:
+    def setupmethod(self):
+        s3 = boto3.client("s3", region_name="us-east-1")
+        s3.create_bucket(Bucket="mybucket")
+
+    def test_should_not_find_bucket(self):
+        # Name of setupmethod is not recognized, so it will not be executed
+        s3 = boto3.client("s3", region_name="us-east-1")
+        with pytest.raises(ClientError):
+            s3.head_bucket(Bucket="mybucket")
+
+
 @mock_s3
 class TestWithPublicMethod(unittest.TestCase):
     def ensure_bucket_exists(self):

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_core/test_decorator_calls.py::TestWithSetup_LowercaseU::test_should_find_bucket tests/test_core/test_decorator_calls.py::TestWithSetupMethod::test_should_find_bucket tests/test_core/test_decorator_calls.py::TestWithNestedClasses::TestWithSetup::test_should_not_find_bucket_from_test_method tests/test_core/test_decorator_calls.py::TestSetUpInBaseClass::test_a_thing tests/test_core/test_decorator_calls.py::TestWithInvalidSetupMethod::test_should_not_find_bucket tests/test_core/test_decorator_calls.py::TestWithSetupMethod::test_should_not_find_unknown_bucket tests/test_core/test_decorator_calls.py::test_context_manager tests/test_core/test_decorator_calls.py::Tester::test_still_the_same tests/test_core/test_decorator_calls.py::TestWithPseudoPrivateMethod::test_should_not_find_bucket tests/test_core/test_decorator_calls.py::TestWithSetup_UppercaseU::test_should_find_bucket tests/test_core/test_decorator_calls.py::TestWithPublicMethod::test_should_not_find_bucket tests/test_core/test_decorator_calls.py::test_decorator_start_and_stop tests/test_core/test_decorator_calls.py::TesterWithSetup::test_still_the_same tests/test_core/test_decorator_calls.py::TestWithNestedClasses::NestedClass::test_should_find_bucket tests/test_core/test_decorator_calls.py::TesterWithStaticmethod::test_no_instance_sent_to_staticmethod tests/test_core/test_decorator_calls.py::TestWithSetup_UppercaseU::test_should_not_find_unknown_bucket tests/test_core/test_decorator_calls.py::TestWithSetup_LowercaseU::test_should_not_find_unknown_bucket tests/test_core/test_decorator_calls.py::TestWithNestedClasses::TestWithSetup::test_should_find_bucket tests/test_core/test_decorator_calls.py::test_basic_decorator tests/test_core/test_decorator_calls.py::test_decorater_wrapped_gets_set tests/test_core/test_decorator_calls.py::TestWithPseudoPrivateMethod::test_should_find_bucket tests/test_core/test_decorator_calls.py::TestWithNestedClasses::NestedClass2::test_should_find_bucket tests/test_core/test_decorator_calls.py::Tester::test_the_class tests/test_core/test_decorator_calls.py::TestWithNestedClasses::NestedClass2::test_should_not_find_bucket_from_different_class tests/test_core/test_decorator_calls.py::TestWithPublicMethod::test_should_find_bucket
: '>>>>> End Test Output'
git checkout bb6fb1200f8db61e0d39c9a4da5954469a403fb8 -- tests/test_core/test_decorator_calls.py 2>/dev/null || true
