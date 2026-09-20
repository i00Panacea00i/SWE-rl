#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 06297af6798f26b38717773aab5752a1158aa04c -- conans/test/functional/tools/scm/test_git.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/functional/tools/scm/test_git.py b/conans/test/functional/tools/scm/test_git.py
--- a/conans/test/functional/tools/scm/test_git.py
+++ b/conans/test/functional/tools/scm/test_git.py
@@ -289,6 +289,37 @@ def test_clone_checkout(self):
         assert c.load("source/src/myfile.h") == "myheader!"
         assert c.load("source/CMakeLists.txt") == "mycmake"
 
+    def test_clone_url_not_hidden(self):
+        conanfile = textwrap.dedent("""
+            import os
+            from conan import ConanFile
+            from conan.tools.scm import Git
+            from conan.tools.files import load
+
+            class Pkg(ConanFile):
+                name = "pkg"
+                version = "0.1"
+
+                def layout(self):
+                    self.folders.source = "source"
+
+                def source(self):
+                    git = Git(self)
+                    git.clone(url="{url}", target=".", hide_url=False)
+            """)
+        folder = os.path.join(temp_folder(), "myrepo")
+        url, _ = create_local_git_repo(files={"CMakeLists.txt": "mycmake"}, folder=folder)
+
+        c = TestClient(light=True)
+        c.save({"conanfile.py": conanfile.format(url=url)})
+        c.run("create . -v")
+        # Clone URL is explicitly printed
+        assert f'pkg/0.1: RUN: git clone "{url}"  "."' in c.out
+
+        # It also works in local flow
+        c.run("source .")
+        assert f'conanfile.py (pkg/0.1): RUN: git clone "{url}"  "."' in c.out
+
     def test_clone_target(self):
         # Clone to a different target folder
         # https://github.com/conan-io/conan/issues/14058
@@ -422,6 +453,37 @@ def test_clone_checkout(self):
         assert c.load("source/src/myfile.h") == "myheader!"
         assert c.load("source/CMakeLists.txt") == "mycmake"
 
+    def test_clone_url_not_hidden(self):
+        conanfile = textwrap.dedent("""
+            import os
+            from conan import ConanFile
+            from conan.tools.scm import Git
+            from conan.tools.files import load
+
+            class Pkg(ConanFile):
+                name = "pkg"
+                version = "0.1"
+
+                def layout(self):
+                    self.folders.source = "source"
+
+                def source(self):
+                    git = Git(self)
+                    git.fetch_commit(url="{url}", commit="{commit}", hide_url=False)
+            """)
+        folder = os.path.join(temp_folder(), "myrepo")
+        url, commit = create_local_git_repo(files={"CMakeLists.txt": "mycmake"}, folder=folder)
+
+        c = TestClient(light=True)
+        c.save({"conanfile.py": conanfile.format(url=url, commit=commit)})
+        c.run("create . -v")
+        # Clone URL is explicitly printed
+        assert f'pkg/0.1: RUN: git remote add origin "{url}"' in c.out
+
+        # It also works in local flow
+        c.run("source .")
+        assert f'conanfile.py (pkg/0.1): RUN: git remote add origin "{url}"' in c.out
+
 
 class TestGitCloneWithArgs:
     """ Git cloning passing additional arguments

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail conans/test/functional/tools/scm/test_git.py::TestGitBasicClone::test_clone_url_not_hidden conans/test/functional/tools/scm/test_git.py::TestGitShallowClone::test_clone_url_not_hidden 'conans/test/functional/tools/scm/test_git.py::TestGitBasicSCMFlow::test_branch_flow[True]' 'conans/test/functional/tools/scm/test_git.py::TestGitBasicSCMFlow::test_full_scm[True]' conans/test/functional/tools/scm/test_git.py::test_capture_git_tag conans/test/functional/tools/scm/test_git.py::TestGitCloneWithArgs::test_clone_invalid_branch_argument conans/test/functional/tools/scm/test_git.py::TestGitBasicClone::test_clone_checkout conans/test/functional/tools/scm/test_git.py::TestGitBasicCapture::test_capture_remote_url conans/test/functional/tools/scm/test_git.py::TestGitCaptureSCM::test_capture_commit_modified_config conans/test/functional/tools/scm/test_git.py::TestGitBasicSCMFlowSubfolder::test_full_scm conans/test/functional/tools/scm/test_git.py::TestConanFileSubfolder::test_conanfile_subfolder conans/test/functional/tools/scm/test_git.py::TestGitCaptureSCM::test_capture_remote_url conans/test/functional/tools/scm/test_git.py::TestGitShallowTagClone::test_find_tag_in_remote conans/test/functional/tools/scm/test_git.py::TestGitBasicCapture::test_git_excluded conans/test/functional/tools/scm/test_git.py::TestGitIncluded::test_git_included conans/test/functional/tools/scm/test_git.py::TestGitBasicClone::test_clone_target conans/test/functional/tools/scm/test_git.py::TestGitIncluded::test_git_included_subfolder 'conans/test/functional/tools/scm/test_git.py::TestGitBasicSCMFlow::test_branch_flow[False]' conans/test/functional/tools/scm/test_git.py::TestGitBasicCapture::test_capture_commit_local 'conans/test/functional/tools/scm/test_git.py::TestGitBasicSCMFlow::test_full_scm[False]' conans/test/functional/tools/scm/test_git.py::TestGitCaptureSCM::test_capture_commit_local conans/test/functional/tools/scm/test_git.py::TestGitCloneWithArgs::test_clone_specify_branch_or_tag conans/test/functional/tools/scm/test_git.py::TestGitCaptureSCM::test_capture_commit_modified_config_untracked conans/test/functional/tools/scm/test_git.py::TestGitBasicCapture::test_capture_remote_pushed_commit conans/test/functional/tools/scm/test_git.py::TestGitBasicCapture::test_capture_commit_local_subfolder conans/test/functional/tools/scm/test_git.py::TestGitMonorepoSCMFlow::test_full_scm conans/test/functional/tools/scm/test_git.py::TestGitBasicClone::test_clone_msys2_win_bash conans/test/functional/tools/scm/test_git.py::TestConanFileSubfolder::test_git_run conans/test/functional/tools/scm/test_git.py::TestGitCaptureSCM::test_capture_remote_pushed_commit conans/test/functional/tools/scm/test_git.py::TestGitShallowTagClone::test_detect_commit_not_in_remote
: '>>>>> End Test Output'
git checkout 06297af6798f26b38717773aab5752a1158aa04c -- conans/test/functional/tools/scm/test_git.py 2>/dev/null || true
