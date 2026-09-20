#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 53603b01c7b76ca166788ec6dca460614a883a96 -- tests/test_s3/test_server.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_s3/test_server.py b/tests/test_s3/test_server.py
--- a/tests/test_s3/test_server.py
+++ b/tests/test_s3/test_server.py
@@ -66,6 +66,10 @@ def test_s3_server_bucket_create(key_name):
     content.should.be.a(dict)
     content["Key"].should.equal(key_name)
 
+    res = test_client.head("http://foobaz.localhost:5000")
+    assert res.status_code == 200
+    assert res.headers.get("x-amz-bucket-region") == "us-east-1"
+
     res = test_client.get(f"/{key_name}", "http://foobaz.localhost:5000/")
     res.status_code.should.equal(200)
     res.data.should.equal(b"test value")

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail 'tests/test_s3/test_server.py::test_s3_server_bucket_create[bar+baz]' 'tests/test_s3/test_server.py::test_s3_server_bucket_create[bar_baz]' 'tests/test_s3/test_server.py::test_s3_server_bucket_create[baz' tests/test_s3/test_server.py::test_s3_server_post_without_content_length tests/test_s3/test_server.py::test_s3_server_post_to_bucket tests/test_s3/test_server.py::test_s3_server_get tests/test_s3/test_server.py::test_s3_server_post_unicode_bucket_key tests/test_s3/test_server.py::test_s3_server_post_cors_exposed_header tests/test_s3/test_server.py::test_s3_server_ignore_subdomain_for_bucketnames tests/test_s3/test_server.py::test_s3_server_bucket_versioning tests/test_s3/test_server.py::test_s3_server_post_to_bucket_redirect tests/test_s3/test_server.py::test_s3_server_post_cors
: '>>>>> End Test Output'
git checkout 53603b01c7b76ca166788ec6dca460614a883a96 -- tests/test_s3/test_server.py 2>/dev/null || true
