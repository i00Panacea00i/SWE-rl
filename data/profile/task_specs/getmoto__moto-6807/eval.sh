#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 0b8581ae98f6a2bfa5e8e6e09c0c10d5f9e35d41 -- tests/test_core/test_environ_patching.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_core/test_environ_patching.py b/tests/test_core/test_environ_patching.py
--- a/tests/test_core/test_environ_patching.py
+++ b/tests/test_core/test_environ_patching.py
@@ -7,7 +7,7 @@
 def test_aws_keys_are_patched():
     with mock_ec2():
         patched_value = os.environ[KEY]
-        assert patched_value == "foobar_key"
+        assert patched_value == "FOOBARKEY"
 
 
 def test_aws_keys_can_be_none():
@@ -25,7 +25,7 @@ def test_aws_keys_can_be_none():
         # Verify that the os.environ[KEY] is patched
         with mock_s3():
             patched_value = os.environ[KEY]
-            assert patched_value == "foobar_key"
+            assert patched_value == "FOOBARKEY"
         # Verify that the os.environ[KEY] is unpatched, and reverts to None
         assert os.environ.get(KEY) is None
     finally:

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_core/test_environ_patching.py::test_aws_keys_are_patched tests/test_core/test_environ_patching.py::test_aws_keys_can_be_none
: '>>>>> End Test Output'
git checkout 0b8581ae98f6a2bfa5e8e6e09c0c10d5f9e35d41 -- tests/test_core/test_environ_patching.py 2>/dev/null || true
