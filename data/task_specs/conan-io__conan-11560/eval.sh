#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 345be91a038e1bda707e07a19889953412d358dc -- conans/test/unittests/tools/google/test_bazeldeps.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/unittests/tools/google/test_bazeldeps.py b/conans/test/unittests/tools/google/test_bazeldeps.py
--- a/conans/test/unittests/tools/google/test_bazeldeps.py
+++ b/conans/test/unittests/tools/google/test_bazeldeps.py
@@ -58,7 +58,7 @@ def test_bazeldeps_dependency_buildfiles():
                 assert 'linkopts = ["/DEFAULTLIB:system_lib1"]' in dependency_content
             else:
                 assert 'linkopts = ["-lsystem_lib1"],' in dependency_content
-            assert 'deps = [\n    \n    ":lib1_precompiled",' in dependency_content
+            assert """deps = [\n        # do not sort\n    \n    ":lib1_precompiled",""" in dependency_content
 
 
 def test_bazeldeps_get_lib_file_path_by_basename():
@@ -93,7 +93,7 @@ def test_bazeldeps_get_lib_file_path_by_basename():
                 assert 'linkopts = ["/DEFAULTLIB:system_lib1"]' in dependency_content
             else:
                 assert 'linkopts = ["-lsystem_lib1"],' in dependency_content
-            assert 'deps = [\n    \n    ":liblib1.a_precompiled",' in dependency_content
+            assert 'deps = [\n        # do not sort\n    \n    ":liblib1.a_precompiled",' in dependency_content
 
 
 def test_bazeldeps_dependency_transitive():
@@ -148,7 +148,7 @@ def test_bazeldeps_dependency_transitive():
 
         # Ensure that transitive dependency is referenced by the 'deps' attribute of the direct
         # dependency
-        assert re.search(r'deps =\s*\[\s*":lib1_precompiled",\s*"@TransitiveDepName"',
+        assert re.search(r'deps =\s*\[\s*# do not sort\s*":lib1_precompiled",\s*"@TransitiveDepName"',
                          dependency_content)
 
 
@@ -220,6 +220,7 @@ def test_bazeldeps_shared_library_interface_buildfiles():
     includes=["include"],
     visibility=["//visibility:public"],
     deps = [
+        # do not sort
         ":lib1_precompiled",
     ],
 )

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail conans/test/unittests/tools/google/test_bazeldeps.py::test_bazeldeps_dependency_buildfiles conans/test/unittests/tools/google/test_bazeldeps.py::test_bazeldeps_get_lib_file_path_by_basename conans/test/unittests/tools/google/test_bazeldeps.py::test_bazeldeps_shared_library_interface_buildfiles conans/test/unittests/tools/google/test_bazeldeps.py::test_bazeldeps_dependency_transitive conans/test/unittests/tools/google/test_bazeldeps.py::test_bazeldeps_main_buildfile conans/test/unittests/tools/google/test_bazeldeps.py::test_bazeldeps_build_dependency_buildfiles conans/test/unittests/tools/google/test_bazeldeps.py::test_bazeldeps_interface_buildfiles
: '>>>>> End Test Output'
git checkout 345be91a038e1bda707e07a19889953412d358dc -- conans/test/unittests/tools/google/test_bazeldeps.py 2>/dev/null || true
