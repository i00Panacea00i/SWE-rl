#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e05157f8e05e856d2e9966c30a3150c26b32b86f -- tests/func/test_unprotect.py tests/unit/remote/test_local.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_unprotect.py b/tests/func/test_unprotect.py
--- a/tests/func/test_unprotect.py
+++ b/tests/func/test_unprotect.py
@@ -24,11 +24,14 @@ def test(self):
 
         self.assertTrue(os.access(self.FOO, os.W_OK))
 
-        # NOTE: cache is now unprotected, bceause we try to set write perms
-        # on files that we try to delete, as some filesystems require that
-        # (e.g. NTFS). But it should be restored after the next cache check,
-        # hence why we call `dvc status` here.
-        self.assertTrue(os.access(cache, os.W_OK))
-        ret = main(["status"])
-        self.assertEqual(ret, 0)
+        if os.name == "nt":
+            # NOTE: cache is now unprotected, because NTFS doesn't allow
+            # deleting read-only files, so we have to try to set write perms
+            # on files that we try to delete, which propagates to the cache
+            # file. But it should be restored after the next cache check, hence
+            # why we call `dvc status` here.
+            self.assertTrue(os.access(cache, os.W_OK))
+            ret = main(["status"])
+            self.assertEqual(ret, 0)
+
         self.assertFalse(os.access(cache, os.W_OK))
diff --git a/tests/unit/remote/test_local.py b/tests/unit/remote/test_local.py
--- a/tests/unit/remote/test_local.py
+++ b/tests/unit/remote/test_local.py
@@ -54,11 +54,12 @@ def test_is_protected(tmp_dir, dvc, link_name):
     remote.unprotect(link)
 
     assert not remote.is_protected(link)
-    if link_name == "symlink" and os.name == "nt":
-        # NOTE: Windows symlink perms don't propagate to the target
-        assert remote.is_protected(foo)
-    else:
+    if os.name == "nt" and link_name == "hardlink":
+        # NOTE: NTFS doesn't allow deleting read-only files, which forces us to
+        # set write perms on the link, which propagates to the source.
         assert not remote.is_protected(foo)
+    else:
+        assert remote.is_protected(foo)
 
 
 @pytest.mark.parametrize("err", [errno.EPERM, errno.EACCES])

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/unit/remote/test_local.py::test_is_protected[symlink]' 'tests/unit/remote/test_local.py::test_is_protected[hardlink]' 'tests/unit/remote/test_local.py::test_protect_ignore_errors[1]' tests/unit/remote/test_local.py::test_status_download_optimization 'tests/unit/remote/test_local.py::test_protect_ignore_errors[13]' tests/unit/remote/test_local.py::test_protect_ignore_erofs
: '>>>>> End Test Output'
git checkout e05157f8e05e856d2e9966c30a3150c26b32b86f -- tests/func/test_unprotect.py tests/unit/remote/test_local.py 2>/dev/null || true
