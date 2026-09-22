#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 94fe86afe8564648c41e30cdf7d4fa122b0b7ac7 -- tests/func/test_import.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_import.py b/tests/func/test_import.py
--- a/tests/func/test_import.py
+++ b/tests/func/test_import.py
@@ -4,7 +4,7 @@
 from tests.utils import trees_equal
 
 
-def test_import(repo_dir, dvc_repo, erepo):
+def test_import(repo_dir, git, dvc_repo, erepo):
     src = erepo.FOO
     dst = erepo.FOO + "_imported"
 
@@ -13,9 +13,10 @@ def test_import(repo_dir, dvc_repo, erepo):
     assert os.path.exists(dst)
     assert os.path.isfile(dst)
     assert filecmp.cmp(repo_dir.FOO, dst, shallow=False)
+    assert git.git.check_ignore(dst)
 
 
-def test_import_dir(repo_dir, dvc_repo, erepo):
+def test_import_dir(repo_dir, git, dvc_repo, erepo):
     src = erepo.DATA_DIR
     dst = erepo.DATA_DIR + "_imported"
 
@@ -24,9 +25,10 @@ def test_import_dir(repo_dir, dvc_repo, erepo):
     assert os.path.exists(dst)
     assert os.path.isdir(dst)
     trees_equal(src, dst)
+    assert git.git.check_ignore(dst)
 
 
-def test_import_rev(repo_dir, dvc_repo, erepo):
+def test_import_rev(repo_dir, git, dvc_repo, erepo):
     src = "version"
     dst = src
 
@@ -36,3 +38,4 @@ def test_import_rev(repo_dir, dvc_repo, erepo):
     assert os.path.isfile(dst)
     with open(dst, "r+") as fobj:
         assert fobj.read() == "branch"
+    assert git.git.check_ignore(dst)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_import.py::test_import_rev tests/func/test_import.py::test_import tests/func/test_import.py::test_import_dir
: '>>>>> End Test Output'
git checkout 94fe86afe8564648c41e30cdf7d4fa122b0b7ac7 -- tests/func/test_import.py 2>/dev/null || true
