#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout b43eb83956f053a47cc3897cfdd57b9da13a16e6 -- conans/test/unittests/tools/files/test_patches.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/unittests/tools/files/test_patches.py b/conans/test/unittests/tools/files/test_patches.py
--- a/conans/test/unittests/tools/files/test_patches.py
+++ b/conans/test/unittests/tools/files/test_patches.py
@@ -121,7 +121,7 @@ def test_single_patch_description(mock_patch_ng):
         conanfile = ConanFileMock()
         conanfile.display_name = 'mocked/ref'
         patch(conanfile, patch_file='patch-file', patch_description='patch_description')
-    assert 'mocked/ref: Apply patch: patch_description\n' == output.getvalue()
+    assert 'mocked/ref: Apply patch (file): patch_description\n' == output.getvalue()
 
 
 def test_single_patch_extra_fields(mock_patch_ng):
@@ -173,8 +173,10 @@ def test_multiple_no_version(mock_patch_ng):
              'patch_description': 'Needed to build with modern clang compilers.'}
         ]}
         apply_conandata_patches(conanfile)
+    assert 'mocked/ref: Apply patch (file): patches/0001-buildflatbuffers-cmake.patch\n' \
+           in output.getvalue()
     assert 'mocked/ref: Apply patch (backport): Needed to build with modern clang compilers.\n' \
-           == output.getvalue()
+           in output.getvalue()
 
 
 def test_multiple_with_version(mock_patch_ng):
@@ -210,8 +212,10 @@ def test_multiple_with_version(mock_patch_ng):
 
         conanfile.version = "1.11.0"
         apply_conandata_patches(conanfile)
+        assert 'mocked/ref: Apply patch (file): patches/0001-buildflatbuffers-cmake.patch\n' \
+               in output.getvalue()
         assert 'mocked/ref: Apply patch (backport): Needed to build with modern clang compilers.\n' \
-               == output.getvalue()
+               in output.getvalue()
 
         # Ensure the function is not mutating the `conan_data` structure
         assert conanfile.conan_data == conandata_contents

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail conans/test/unittests/tools/files/test_patches.py::test_multiple_with_version conans/test/unittests/tools/files/test_patches.py::test_single_patch_description conans/test/unittests/tools/files/test_patches.py::test_multiple_no_version conans/test/unittests/tools/files/test_patches.py::test_single_patch_arguments conans/test/unittests/tools/files/test_patches.py::test_single_apply_fail conans/test/unittests/tools/files/test_patches.py::test_single_patch_type conans/test/unittests/tools/files/test_patches.py::test_single_patch_file_from_forced_build conans/test/unittests/tools/files/test_patches.py::test_base_path conans/test/unittests/tools/files/test_patches.py::test_single_patch_string conans/test/unittests/tools/files/test_patches.py::test_single_patch_extra_fields conans/test/unittests/tools/files/test_patches.py::test_single_patch_file conans/test/unittests/tools/files/test_patches.py::test_apply_in_build_from_patch_in_source conans/test/unittests/tools/files/test_patches.py::test_single_no_patchset
: '>>>>> End Test Output'
git checkout b43eb83956f053a47cc3897cfdd57b9da13a16e6 -- conans/test/unittests/tools/files/test_patches.py 2>/dev/null || true
