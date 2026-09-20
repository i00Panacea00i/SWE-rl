#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout a3d2fbcefe1cbdff55efb085d7c177c3d1e32dc8 -- test/unittests/tools/files/test_rm.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test/unittests/tools/files/test_rm.py b/test/unittests/tools/files/test_rm.py
--- a/test/unittests/tools/files/test_rm.py
+++ b/test/unittests/tools/files/test_rm.py
@@ -1,4 +1,5 @@
 import os
+import pytest
 
 # Check it is importable from tools
 from conan.tools.files import rm, chdir
@@ -63,3 +64,46 @@ def test_remove_files_by_mask_non_recursively():
 
     assert os.path.exists(os.path.join(tmpdir, "1.txt"))
     assert os.path.exists(os.path.join(tmpdir, "subdir", "2.txt"))
+
+
+@pytest.mark.parametrize("recursive", [False, True])
+@pytest.mark.parametrize("results", [
+    ["*.dll", ("foo.dll",)],
+    [("*.dll",), ("foo.dll",)],
+    [["*.dll"], ("foo.dll",)],
+    [("*.dll", "*.lib"), ("foo.dll", "foo.dll.lib")],
+])
+def test_exclude_pattern_from_remove_list(recursive, results):
+    """ conan.tools.files.rm should not remove files that match the pattern but are excluded
+        by the excludes parameter.
+        It should obey the recursive parameter, only excluding the files in the root folder in case
+        it is False.
+    """
+    excludes, expected_files = results
+    temporary_folder = temp_folder()
+    with chdir(None, temporary_folder):
+        os.makedirs("subdir")
+
+    save_files(temporary_folder, {
+        "1.txt": "",
+        "1.pdb": "",
+        "1.pdb1": "",
+        "foo.dll": "",
+        "foo.dll.lib": "",
+        os.path.join("subdir", "2.txt"): "",
+        os.path.join("subdir", "2.pdb"): "",
+        os.path.join("subdir", "foo.dll"): "",
+        os.path.join("subdir", "foo.dll.lib"): "",
+        os.path.join("subdir", "2.pdb1"): ""})
+
+    rm(None, "*", temporary_folder, excludes=excludes, recursive=recursive)
+
+    for it in expected_files:
+        assert os.path.exists(os.path.join(temporary_folder, it))
+    assert not os.path.exists(os.path.join(temporary_folder, "1.pdb"))
+
+    # Check the recursive parameter and subfolder
+    condition = (lambda x: not x) if recursive else (lambda x: x)
+    assert condition(os.path.exists(os.path.join(temporary_folder, "subdir", "2.pdb")))
+    for it in expected_files:
+        assert os.path.exists(os.path.join(temporary_folder, "subdir", it))

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'test/unittests/tools/files/test_rm.py::test_exclude_pattern_from_remove_list[results3-True]' 'test/unittests/tools/files/test_rm.py::test_exclude_pattern_from_remove_list[results0-True]' 'test/unittests/tools/files/test_rm.py::test_exclude_pattern_from_remove_list[results0-False]' 'test/unittests/tools/files/test_rm.py::test_exclude_pattern_from_remove_list[results1-False]' 'test/unittests/tools/files/test_rm.py::test_exclude_pattern_from_remove_list[results2-False]' 'test/unittests/tools/files/test_rm.py::test_exclude_pattern_from_remove_list[results1-True]' 'test/unittests/tools/files/test_rm.py::test_exclude_pattern_from_remove_list[results2-True]' 'test/unittests/tools/files/test_rm.py::test_exclude_pattern_from_remove_list[results3-False]' test/unittests/tools/files/test_rm.py::test_remove_files_by_mask_non_recursively test/unittests/tools/files/test_rm.py::test_remove_files_by_mask_recursively
: '>>>>> End Test Output'
git checkout a3d2fbcefe1cbdff55efb085d7c177c3d1e32dc8 -- test/unittests/tools/files/test_rm.py 2>/dev/null || true
