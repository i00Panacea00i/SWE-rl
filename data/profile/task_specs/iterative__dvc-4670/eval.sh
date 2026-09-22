#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 15b1e7072bf4c133a640507f59011d32501a968f -- tests/unit/test_path_info.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/test_path_info.py b/tests/unit/test_path_info.py
--- a/tests/unit/test_path_info.py
+++ b/tests/unit/test_path_info.py
@@ -1,4 +1,5 @@
 import copy
+import os
 import pathlib
 
 import pytest
@@ -102,3 +103,17 @@ def test_url_replace_path():
     assert u.params == new_u.params
     assert u.query == new_u.query
     assert u.fragment == new_u.fragment
+
+
+@pytest.mark.parametrize(
+    "p1, p2",
+    [
+        ("/foo/bar", "/baz"),
+        ("/baz", "/foo/bar"),
+        ("/foo/bar", "../baz"),
+        ("../baz", "/foo/bar"),
+    ],
+)
+def test_relative_to_different_subpath(p1, p2):
+    expected = PathInfo(os.path.relpath(p1, p2))
+    assert PathInfo(p1).relative_to(PathInfo(p2)) == expected

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/unit/test_path_info.py::test_relative_to_different_subpath[/foo/bar-../baz]' 'tests/unit/test_path_info.py::test_relative_to_different_subpath[/baz-/foo/bar]' 'tests/unit/test_path_info.py::test_relative_to_different_subpath[../baz-/foo/bar]' 'tests/unit/test_path_info.py::test_relative_to_different_subpath[/foo/bar-/baz]' 'tests/unit/test_path_info.py::test_path_info_as_posix[/some/abs/path-/some/abs/path-posix]' tests/unit/test_path_info.py::test_https_url_info_str 'tests/unit/test_path_info.py::test_url_info_parent[URLInfo]' 'tests/unit/test_path_info.py::test_url_info_eq[CloudURLInfo]' 'tests/unit/test_path_info.py::test_url_info_parent[CloudURLInfo]' 'tests/unit/test_path_info.py::test_url_info_eq[URLInfo]' 'tests/unit/test_path_info.py::test_url_info_deepcopy[CloudURLInfo]' 'tests/unit/test_path_info.py::test_path_info_as_posix[some/rel/path-some/rel/path-posix]' 'tests/unit/test_path_info.py::test_url_info_parents[CloudURLInfo]' 'tests/unit/test_path_info.py::test_path_info_as_posix[../../../../..-../../../../..-posix]' 'tests/unit/test_path_info.py::test_url_info_str[URLInfo]' 'tests/unit/test_path_info.py::test_url_info_deepcopy[URLInfo]' 'tests/unit/test_path_info.py::test_path_info_as_posix[..\windows\rel\path-../windows/rel/path-nt]' 'tests/unit/test_path_info.py::test_path_info_as_posix[..\..\..\..\..-../../../../..-nt]' 'tests/unit/test_path_info.py::test_url_info_parents[URLInfo]' 'tests/unit/test_path_info.py::test_url_info_deepcopy[HTTPURLInfo]' 'tests/unit/test_path_info.py::test_path_info_as_posix[../some/rel/path-../some/rel/path-posix]' 'tests/unit/test_path_info.py::test_url_info_str[CloudURLInfo]' 'tests/unit/test_path_info.py::test_path_info_as_posix[windows\relpath-windows/relpath-nt]' tests/unit/test_path_info.py::test_url_replace_path
: '>>>>> End Test Output'
git checkout 15b1e7072bf4c133a640507f59011d32501a968f -- tests/unit/test_path_info.py 2>/dev/null || true
