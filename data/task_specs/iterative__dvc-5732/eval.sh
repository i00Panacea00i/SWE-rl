#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 4d4f9427d1e57fd7c3db68965e41d95d2b197339 -- tests/unit/fs/test_s3.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/fs/test_s3.py b/tests/unit/fs/test_s3.py
--- a/tests/unit/fs/test_s3.py
+++ b/tests/unit/fs/test_s3.py
@@ -29,6 +29,22 @@ def test_init(dvc):
     assert fs.path_info == url
 
 
+def test_verify_ssl_default_param(dvc):
+    config = {
+        "url": url,
+    }
+    fs = S3FileSystem(dvc, config)
+
+    assert fs.ssl_verify
+
+
+def test_ssl_verify_bool_param(dvc):
+    config = {"url": url, "ssl_verify": False}
+    fs = S3FileSystem(dvc, config)
+
+    assert fs.ssl_verify == config["ssl_verify"]
+
+
 def test_grants(dvc):
     config = {
         "url": url,

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/unit/fs/test_s3.py::test_verify_ssl_default_param tests/unit/fs/test_s3.py::test_ssl_verify_bool_param tests/unit/fs/test_s3.py::test_get_s3_connection_error tests/unit/fs/test_s3.py::test_grants_mutually_exclusive_acl_error tests/unit/fs/test_s3.py::test_get_bucket tests/unit/fs/test_s3.py::test_get_s3_no_credentials tests/unit/fs/test_s3.py::test_grants tests/unit/fs/test_s3.py::test_sse_kms_key_id tests/unit/fs/test_s3.py::test_key_id_and_secret tests/unit/fs/test_s3.py::test_init tests/unit/fs/test_s3.py::test_get_s3_connection_error_endpoint
: '>>>>> End Test Output'
git checkout 4d4f9427d1e57fd7c3db68965e41d95d2b197339 -- tests/unit/fs/test_s3.py 2>/dev/null || true
