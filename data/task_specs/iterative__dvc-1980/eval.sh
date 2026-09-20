#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 45f94e36b25e8f43a4a70edd8a779286273ec70f -- tests/func/test_install.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_install.py b/tests/func/test_install.py
--- a/tests/func/test_install.py
+++ b/tests/func/test_install.py
@@ -15,21 +15,44 @@ class TestInstall(object):
     def _hook(self, name):
         return os.path.join(".git", "hooks", name)
 
-    @pytest.fixture(autouse=True)
-    def setUp(self, dvc):
-        ret = main(["install"])
-        assert ret == 0
+    def test_should_create_hooks(self, dvc):
+        assert main(["install"]) == 0
+
+        hooks_with_commands = [
+            ("post-checkout", "exec dvc checkout"),
+            ("pre-commit", "exec dvc status"),
+            ("pre-push", "exec dvc push"),
+        ]
+
+        for fname, command in hooks_with_commands:
+            assert os.path.isfile(self._hook(fname))
+
+            with open(self._hook(fname), "r") as fobj:
+                assert command in fobj.read()
+
+    def test_should_append_hooks_if_file_already_exists(self, dvc):
+        with open(self._hook("post-checkout"), "w") as fobj:
+            fobj.write("#!/bin/sh\n" "echo hello\n")
+
+        assert main(["install"]) == 0
 
-    def test_should_not_install_twice(self, dvc):
-        ret = main(["install"])
-        assert ret != 0
+        expected_script = "#!/bin/sh\n" "echo hello\n" "exec dvc checkout\n"
 
-    def test_should_create_hooks(self):
-        assert os.path.isfile(self._hook("post-checkout"))
-        assert os.path.isfile(self._hook("pre-commit"))
-        assert os.path.isfile(self._hook("pre-push"))
+        with open(self._hook("post-checkout"), "r") as fobj:
+            assert fobj.read() == expected_script
+
+    def test_should_be_idempotent(self, dvc):
+        assert main(["install"]) == 0
+        assert main(["install"]) == 0
+
+        expected_script = "#!/bin/sh\n" "exec dvc checkout\n"
+
+        with open(self._hook("post-checkout"), "r") as fobj:
+            assert fobj.read() == expected_script
 
     def test_should_post_checkout_hook_checkout(self, repo_dir, dvc):
+        assert main(["install"]) == 0
+
         stage_file = repo_dir.FOO + Stage.STAGE_FILE_SUFFIX
 
         dvc.add(repo_dir.FOO)
@@ -42,6 +65,8 @@ def test_should_post_checkout_hook_checkout(self, repo_dir, dvc):
         assert os.path.isfile(repo_dir.FOO)
 
     def test_should_pre_push_hook_push(self, repo_dir, dvc):
+        assert main(["install"]) == 0
+
         temp = repo_dir.mkdtemp()
         git_remote = os.path.join(temp, "project.git")
         storage_path = os.path.join(temp, "dvc_storage")

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_install.py::TestInstall::test_should_append_hooks_if_file_already_exists tests/func/test_install.py::TestInstall::test_should_be_idempotent tests/func/test_install.py::TestInstall::test_should_create_hooks tests/func/test_install.py::TestInstall::test_should_pre_push_hook_push tests/func/test_install.py::TestInstall::test_should_post_checkout_hook_checkout
: '>>>>> End Test Output'
git checkout 45f94e36b25e8f43a4a70edd8a779286273ec70f -- tests/func/test_install.py 2>/dev/null || true
