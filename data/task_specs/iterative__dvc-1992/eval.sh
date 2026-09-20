#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout a0c089045b9a00d75fb41730c4bae7658aa9e14a -- tests/func/test_add.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_add.py b/tests/func/test_add.py
--- a/tests/func/test_add.py
+++ b/tests/func/test_add.py
@@ -268,6 +268,15 @@ def test(self):
             self.assertEqual(ret, 0)
             self.assertEqual(file_md5_counter.mock.call_count, 1)
 
+            os.rename(self.FOO, self.FOO + ".back")
+            ret = main(["checkout"])
+            self.assertEqual(ret, 0)
+            self.assertEqual(file_md5_counter.mock.call_count, 1)
+
+            ret = main(["status"])
+            self.assertEqual(ret, 0)
+            self.assertEqual(file_md5_counter.mock.call_count, 1)
+
 
 class TestShouldUpdateStateEntryForDirectoryAfterAdd(TestDvc):
     def test(self):
@@ -291,6 +300,15 @@ def test(self):
             self.assertEqual(ret, 0)
             self.assertEqual(file_md5_counter.mock.call_count, 3)
 
+            os.rename(self.DATA_DIR, self.DATA_DIR + ".back")
+            ret = main(["checkout"])
+            self.assertEqual(ret, 0)
+            self.assertEqual(file_md5_counter.mock.call_count, 3)
+
+            ret = main(["status"])
+            self.assertEqual(ret, 0)
+            self.assertEqual(file_md5_counter.mock.call_count, 3)
+
 
 class TestAddCommit(TestDvc):
     def test(self):

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_add.py::TestShouldUpdateStateEntryForFileAfterAdd::test tests/func/test_add.py::TestShouldUpdateStateEntryForDirectoryAfterAdd::test tests/func/test_add.py::TestAddExternalLocalFile::test tests/func/test_add.py::TestAddDirectory::test tests/func/test_add.py::TestDoubleAddUnchanged::test_dir tests/func/test_add.py::TestShouldPlaceStageInDataDirIfRepositoryBelowSymlink::test tests/func/test_add.py::TestAddDirWithExistingCache::test tests/func/test_add.py::TestAddFileInDir::test tests/func/test_add.py::TestAddDirectoryRecursive::test tests/func/test_add.py::TestAdd::test tests/func/test_add.py::TestShouldCollectDirCacheOnlyOnce::test tests/func/test_add.py::TestShouldAddDataFromInternalSymlink::test tests/func/test_add.py::TestAddCommit::test tests/func/test_add.py::TestShouldCleanUpAfterFailedAdd::test tests/func/test_add.py::TestShouldThrowProperExceptionOnCorruptedStageFile::test tests/func/test_add.py::TestAddDirectoryWithForwardSlash::test tests/func/test_add.py::TestAddFilename::test tests/func/test_add.py::TestAdd::test_unicode tests/func/test_add.py::TestAddModifiedDir::test tests/func/test_add.py::TestAddUnupportedFile::test tests/func/test_add.py::TestShouldNotTrackGitInternalFiles::test tests/func/test_add.py::TestShouldAddDataFromExternalSymlink::test tests/func/test_add.py::TestCmdAdd::test tests/func/test_add.py::TestDoubleAddUnchanged::test_file tests/func/test_add.py::TestAddTrackedFile::test tests/func/test_add.py::TestShouldNotCheckCacheForDirIfCacheMetadataDidNotChange::test tests/func/test_add.py::TestAddCmdDirectoryRecursive::test tests/func/test_add.py::TestAddLocalRemoteFile::test
: '>>>>> End Test Output'
git checkout a0c089045b9a00d75fb41730c4bae7658aa9e14a -- tests/func/test_add.py 2>/dev/null || true
