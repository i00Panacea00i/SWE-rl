#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 02daaf391afa31fed3c04413049eece6579b227c -- tests/func/test_data_cloud.py tests/func/test_gc.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_data_cloud.py b/tests/func/test_data_cloud.py
--- a/tests/func/test_data_cloud.py
+++ b/tests/func/test_data_cloud.py
@@ -367,7 +367,7 @@ def _test_cloud(self, remote=None):
         self.assertTrue(os.path.isfile(cache_dir))
 
         # NOTE: check if remote gc works correctly on directories
-        self.main(["gc", "-c", "-f"] + args)
+        self.main(["gc", "-cw", "-f"] + args)
         shutil.move(
             self.dvc.cache.local.cache_dir,
             self.dvc.cache.local.cache_dir + ".back",
diff --git a/tests/func/test_gc.py b/tests/func/test_gc.py
--- a/tests/func/test_gc.py
+++ b/tests/func/test_gc.py
@@ -236,6 +236,20 @@ def test_gc_without_workspace_raises_error(tmp_dir, dvc):
         dvc.gc(force=True, workspace=False)
 
 
+def test_gc_cloud_with_or_without_specifier(tmp_dir, erepo_dir):
+    dvc = erepo_dir.dvc
+    with erepo_dir.chdir():
+        from dvc.exceptions import InvalidArgumentError
+
+        with pytest.raises(InvalidArgumentError):
+            dvc.gc(force=True, cloud=True)
+
+        dvc.gc(cloud=True, all_tags=True)
+        dvc.gc(cloud=True, all_commits=True)
+        dvc.gc(cloud=True, all_branches=True)
+        dvc.gc(cloud=True, all_commits=False, all_branches=True, all_tags=True)
+
+
 def test_gc_without_workspace_on_tags_branches_commits(tmp_dir, dvc):
     dvc.gc(force=True, all_tags=True)
     dvc.gc(force=True, all_commits=True)
@@ -253,6 +267,13 @@ def test_gc_without_workspace(tmp_dir, dvc, caplog):
     assert "Invalid Arguments" in caplog.text
 
 
+def test_gc_cloud_without_any_specifier(tmp_dir, dvc, caplog):
+    with caplog.at_level(logging.WARNING, logger="dvc"):
+        assert main(["gc", "-cvf"]) == 255
+
+    assert "Invalid Arguments" in caplog.text
+
+
 def test_gc_with_possible_args_positive(tmp_dir, dvc):
     for flag in [
         "-w",
@@ -274,5 +295,5 @@ def test_gc_cloud_positive(tmp_dir, dvc, tmp_path_factory):
 
     dvc.push()
 
-    for flag in ["-c", "-ca", "-cT", "-caT", "-cwT"]:
+    for flag in ["-cw", "-ca", "-cT", "-caT", "-cwT"]:
         assert main(["gc", "-vf", flag]) == 0

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_gc.py::test_gc_cloud_without_any_specifier tests/func/test_gc.py::test_gc_cloud_with_or_without_specifier tests/func/test_data_cloud.py::TestDataCloudErrorCLI::test_error tests/func/test_gc.py::test_gc_with_possible_args_positive tests/func/test_gc.py::test_gc_without_workspace_on_tags_branches_commits tests/func/test_gc.py::test_gc_cloud_positive tests/func/test_gc.py::test_gc_without_workspace tests/func/test_gc.py::test_gc_without_workspace_raises_error tests/func/test_data_cloud.py::TestDataCloud::test
: '>>>>> End Test Output'
git checkout 02daaf391afa31fed3c04413049eece6579b227c -- tests/func/test_data_cloud.py tests/func/test_gc.py 2>/dev/null || true
