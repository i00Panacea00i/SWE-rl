#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout be6128470f6e7d590f889b20ea24bdde115f059e -- tests/unit/remote/test_webhdfs.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/remote/test_webhdfs.py b/tests/unit/remote/test_webhdfs.py
--- a/tests/unit/remote/test_webhdfs.py
+++ b/tests/unit/remote/test_webhdfs.py
@@ -1,21 +1,54 @@
+from unittest.mock import Mock, create_autospec
+
+import pytest
+import requests
+
 from dvc.fs.webhdfs import WebHDFSFileSystem
 
+host = "host"
+kerberos = False
+kerberos_principal = "principal"
+port = 12345
+proxy_to = "proxy"
+ssl_verify = False
+token = "token"
+use_https = True
 user = "test"
-webhdfs_token = "token"
-webhdfs_alias = "alias-name"
-hdfscli_config = "path/to/cli/config"
-
-
-def test_init(dvc):
-    url = "webhdfs://test@127.0.0.1:50070"
-    config = {
-        "host": url,
-        "webhdfs_token": webhdfs_token,
-        "webhdfs_alias": webhdfs_alias,
-        "hdfscli_config": hdfscli_config,
-        "user": user,
+
+
+@pytest.fixture()
+def webhdfs_config():
+    url = f"webhdfs://{user}@{host}:{port}"
+    url_config = WebHDFSFileSystem._get_kwargs_from_urls(url)
+    return {
+        "kerberos": kerberos,
+        "kerberos_principal": kerberos_principal,
+        "proxy_to": proxy_to,
+        "ssl_verify": ssl_verify,
+        "token": token,
+        "use_https": use_https,
+        **url_config,
     }
 
-    fs = WebHDFSFileSystem(**config)
-    assert fs.fs_args["token"] == webhdfs_token
+
+def test_init(dvc, webhdfs_config):
+    fs = WebHDFSFileSystem(**webhdfs_config)
+    assert fs.fs_args["host"] == host
+    assert fs.fs_args["token"] == token
     assert fs.fs_args["user"] == user
+    assert fs.fs_args["port"] == port
+    assert fs.fs_args["kerberos"] == kerberos
+    assert fs.fs_args["kerb_kwargs"] == {"principal": kerberos_principal}
+    assert fs.fs_args["proxy_to"] == proxy_to
+    assert fs.fs_args["use_https"] == use_https
+
+
+def test_verify_ssl(dvc, webhdfs_config, monkeypatch):
+    mock_session = create_autospec(requests.Session)
+    monkeypatch.setattr(requests, "Session", Mock(return_value=mock_session))
+    # can't have token at the same time as user or proxy_to
+    del webhdfs_config["token"]
+    fs = WebHDFSFileSystem(**webhdfs_config)
+    # ssl verify can't be set until after the file system is instantiated
+    fs.fs  # pylint: disable=pointless-statement
+    assert mock_session.verify == ssl_verify

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/unit/remote/test_webhdfs.py::test_init tests/unit/remote/test_webhdfs.py::test_verify_ssl
: '>>>>> End Test Output'
git checkout be6128470f6e7d590f889b20ea24bdde115f059e -- tests/unit/remote/test_webhdfs.py 2>/dev/null || true
