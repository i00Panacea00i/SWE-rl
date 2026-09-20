#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8bbfe9c151e62952b153f483d3604b57c7e99ab6 -- tests/test_core/test_responses_module.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_core/test_responses_module.py b/tests/test_core/test_responses_module.py
new file mode 100644
--- /dev/null
+++ b/tests/test_core/test_responses_module.py
@@ -0,0 +1,63 @@
+"""
+Ensure that the responses module plays nice with our mocks
+"""
+
+import boto3
+import requests
+import responses
+from moto import mock_s3, settings
+from unittest import SkipTest, TestCase
+
+
+class TestResponsesModule(TestCase):
+    def setUp(self):
+        if settings.TEST_SERVER_MODE:
+            raise SkipTest("No point in testing responses-decorator in ServerMode")
+
+    @mock_s3
+    @responses.activate
+    def test_moto_first(self):
+
+        """
+        Verify we can activate a user-defined `responses` on top of our Moto mocks
+        """
+        self.moto_responses_compatibility()
+
+    @responses.activate
+    @mock_s3
+    def test_moto_second(self):
+        """
+        Verify we can load Moto after activating a `responses`-mock
+        """
+        self.moto_responses_compatibility()
+
+    def moto_responses_compatibility(self):
+        responses.add(
+            responses.GET, url="http://127.0.0.1/lkdsfjlkdsa", json={"a": "4"},
+        )
+        s3 = boto3.client("s3")
+        s3.create_bucket(Bucket="mybucket")
+        s3.put_object(Bucket="mybucket", Key="name", Body="value")
+        s3.get_object(Bucket="mybucket", Key="name")["Body"].read()
+        with requests.get("http://127.0.0.1/lkdsfjlkdsa",) as r:
+            assert r.json() == {"a": "4"}
+
+    @responses.activate
+    def test_moto_as_late_as_possible(self):
+        """
+        Verify we can load moto after registering a response
+        """
+        responses.add(
+            responses.GET, url="http://127.0.0.1/lkdsfjlkdsa", json={"a": "4"},
+        )
+        with mock_s3():
+            s3 = boto3.client("s3")
+            s3.create_bucket(Bucket="mybucket")
+            s3.put_object(Bucket="mybucket", Key="name", Body="value")
+            # This mock exists within Moto
+            with requests.get("http://127.0.0.1/lkdsfjlkdsa",) as r:
+                assert r.json() == {"a": "4"}
+
+        # And outside of Moto
+        with requests.get("http://127.0.0.1/lkdsfjlkdsa",) as r:
+            assert r.json() == {"a": "4"}

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_core/test_responses_module.py::TestResponsesModule::test_moto_second tests/test_core/test_responses_module.py::TestResponsesModule::test_moto_as_late_as_possible tests/test_core/test_responses_module.py::TestResponsesModule::test_moto_first
: '>>>>> End Test Output'
git checkout 8bbfe9c151e62952b153f483d3604b57c7e99ab6 -- tests/test_core/test_responses_module.py 2>/dev/null || true
