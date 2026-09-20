#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 378486dbf53271ec894b4380f60ec02dc3351516 -- tests/unit/remote/test_http.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/remote/test_http.py b/tests/unit/remote/test_http.py
--- a/tests/unit/remote/test_http.py
+++ b/tests/unit/remote/test_http.py
@@ -23,7 +23,7 @@ def test_public_auth_method(dvc):
 
     fs = HTTPFileSystem(**config)
 
-    assert "auth" not in fs.fs_args["client_args"]
+    assert "auth" not in fs.fs_args["client_kwargs"]
     assert "headers" not in fs.fs_args
 
 
@@ -40,8 +40,8 @@ def test_basic_auth_method(dvc):
 
     fs = HTTPFileSystem(**config)
 
-    assert fs.fs_args["client_args"]["auth"].login == user
-    assert fs.fs_args["client_args"]["auth"].password == password
+    assert fs.fs_args["client_kwargs"]["auth"].login == user
+    assert fs.fs_args["client_kwargs"]["auth"].password == password
 
 
 def test_custom_auth_method(dvc):
@@ -70,7 +70,7 @@ def test_ssl_verify_disable(dvc):
     }
 
     fs = HTTPFileSystem(**config)
-    assert not fs.fs_args["client_args"]["connector"]._ssl
+    assert not fs.fs_args["client_kwargs"]["connector"]._ssl
 
 
 @patch("ssl.SSLContext.load_verify_locations")
@@ -84,7 +84,7 @@ def test_ssl_verify_custom_cert(dvc, mocker):
     fs = HTTPFileSystem(**config)
 
     assert isinstance(
-        fs.fs_args["client_args"]["connector"]._ssl, ssl.SSLContext
+        fs.fs_args["client_kwargs"]["connector"]._ssl, ssl.SSLContext
     )
 
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/unit/remote/test_http.py::test_basic_auth_method tests/unit/remote/test_http.py::test_public_auth_method tests/unit/remote/test_http.py::test_ssl_verify_disable tests/unit/remote/test_http.py::test_ssl_verify_custom_cert tests/unit/remote/test_http.py::test_custom_auth_method tests/unit/remote/test_http.py::test_http_method tests/unit/remote/test_http.py::test_download_fails_on_error_code
: '>>>>> End Test Output'
git checkout 378486dbf53271ec894b4380f60ec02dc3351516 -- tests/unit/remote/test_http.py 2>/dev/null || true
