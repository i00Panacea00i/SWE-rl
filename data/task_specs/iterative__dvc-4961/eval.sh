#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout c989b28eae536f08767d3cb32e790187d63a581b -- tests/unit/utils/test_utils.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/utils/test_utils.py b/tests/unit/utils/test_utils.py
--- a/tests/unit/utils/test_utils.py
+++ b/tests/unit/utils/test_utils.py
@@ -149,6 +149,31 @@ def test_resolve_output(inp, out, is_dir, expected, mocker):
         ["something.dvc:name", ("something.dvc", "name"), None],
         ["../something.dvc:name", ("../something.dvc", "name"), None],
         ["file", (None, "file"), None],
+        ["build@15", (None, "build@15"), None],
+        ["build@{'level': 35}", (None, "build@{'level': 35}"), None],
+        [":build@15", ("dvc.yaml", "build@15"), None],
+        [":build@{'level': 35}", ("dvc.yaml", "build@{'level': 35}"), None],
+        ["dvc.yaml:build@15", ("dvc.yaml", "build@15"), None],
+        [
+            "dvc.yaml:build@{'level': 35}",
+            ("dvc.yaml", "build@{'level': 35}"),
+            None,
+        ],
+        [
+            "build2@{'level': [1, 2, 3]}",
+            (None, "build2@{'level': [1, 2, 3]}"),
+            None,
+        ],
+        [
+            ":build2@{'level': [1, 2, 3]}",
+            ("dvc.yaml", "build2@{'level': [1, 2, 3]}"),
+            None,
+        ],
+        [
+            "dvc.yaml:build2@{'level': [1, 2, 3]}",
+            ("dvc.yaml", "build2@{'level': [1, 2, 3]}"),
+            None,
+        ],
     ],
 )
 def test_parse_target(inp, out, default):

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail 'tests/unit/utils/test_utils.py::test_parse_target[:build@{'"'"'level'"'"':' 'tests/unit/utils/test_utils.py::test_parse_target[build@{'"'"'level'"'"':' 'tests/unit/utils/test_utils.py::test_parse_target[dvc.yaml:build2@{'"'"'level'"'"':' 'tests/unit/utils/test_utils.py::test_parse_target[:build2@{'"'"'level'"'"':' 'tests/unit/utils/test_utils.py::test_parse_target[dvc.yaml:build@{'"'"'level'"'"':' 'tests/unit/utils/test_utils.py::test_parse_target[build2@{'"'"'level'"'"':' 'tests/unit/utils/test_utils.py::test_parse_target[../models/stage.dvc-out5-def]' tests/unit/utils/test_utils.py::test_tmp_fname 'tests/unit/utils/test_utils.py::test_resolve_output[dir-other_dir-True-other_dir/dir]' 'tests/unit/utils/test_utils.py::test_resolve_output[target-file_target-False-file_target]' tests/unit/utils/test_utils.py::test_relpath 'tests/unit/utils/test_utils.py::test_resolve_output[dir-None-False-dir]' 'tests/unit/utils/test_utils.py::test_parse_target[stage.dvc-out3-None]' 'tests/unit/utils/test_utils.py::test_resolve_output[target-dir/subdir-True-dir/subdir/target]' 'tests/unit/utils/test_utils.py::test_to_chunks_chunk_size[3-expected_chunks2]' 'tests/unit/utils/test_utils.py::test_to_chunks_num_chunks[2-expected_chunks2]' 'tests/unit/utils/test_utils.py::test_dict_sha256[d0-f472eda60f09660a4750e8b3208cf90b3a3b24e5f42e0371d829710e9464d74a]' 'tests/unit/utils/test_utils.py::test_to_chunks_should_raise[None-None]' 'tests/unit/utils/test_utils.py::test_fix_env_pyenv[/pyenv/bin:/pyenv/libexec:/pyenv/plugins/plugin:/orig/path1:/orig/path2-/orig/path1:/orig/path2]' 'tests/unit/utils/test_utils.py::test_to_chunks_should_raise[1-2]' 'tests/unit/utils/test_utils.py::test_parse_target[something.dvc:name-out8-None]' 'tests/unit/utils/test_utils.py::test_dict_sha256[d1-a239b67073bd58affcdb81fff3305d1726c6e7f9c86f3d4fca0e92e8147dc7b0]' 'tests/unit/utils/test_utils.py::test_resolve_output[dir-other_dir-False-other_dir]' tests/unit/utils/test_utils.py::test_hint_on_lockfile 'tests/unit/utils/test_utils.py::test_to_chunks_chunk_size[2-expected_chunks1]' 'tests/unit/utils/test_utils.py::test_parse_target[dvc.yaml-out0-None]' 'tests/unit/utils/test_utils.py::test_fix_env_pyenv[/pyenv/bin:/pyenv/libexec:/orig/path1:/orig/path2-/orig/path1:/orig/path2]' 'tests/unit/utils/test_utils.py::test_fix_env_pyenv[/pyenv/bin:/some/libexec:/pyenv/plugins/plugin:/orig/path1:/orig/path2-/orig/path1:/orig/path2]' 'tests/unit/utils/test_utils.py::test_fix_env_pyenv[/orig/path1:/orig/path2:/pyenv/bin:/pyenv/libexec-/orig/path1:/orig/path2:/pyenv/bin:/pyenv/libexec]' 'tests/unit/utils/test_utils.py::test_parse_target[dvc.yaml:name-out1-None]' 'tests/unit/utils/test_utils.py::test_parse_target[../something.dvc:name-out9-None]' 'tests/unit/utils/test_utils.py::test_parse_target[build@15-out11-None]' 'tests/unit/utils/test_utils.py::test_parse_target[dvc.yaml:build@15-out15-None]' 'tests/unit/utils/test_utils.py::test_resolve_output[target-None-False-target]' tests/unit/utils/test_utils.py::test_file_md5 'tests/unit/utils/test_utils.py::test_to_chunks_chunk_size[1-expected_chunks0]' 'tests/unit/utils/test_utils.py::test_resolve_output[target-dir-True-dir/target]' 'tests/unit/utils/test_utils.py::test_parse_target[:name-out7-default]' 'tests/unit/utils/test_utils.py::test_parse_target[:name-out2-None]' 'tests/unit/utils/test_utils.py::test_parse_target[:build@15-out13-None]' 'tests/unit/utils/test_utils.py::test_parse_target[:name-out6-default]' 'tests/unit/utils/test_utils.py::test_parse_target[dvc.yaml:name-out4-None]' 'tests/unit/utils/test_utils.py::test_to_chunks_num_chunks[4-expected_chunks0]' 'tests/unit/utils/test_utils.py::test_fix_env_pyenv[/orig/path1:/orig/path2-/orig/path1:/orig/path2]' 'tests/unit/utils/test_utils.py::test_to_chunks_num_chunks[3-expected_chunks1]' 'tests/unit/utils/test_utils.py::test_resolve_output[dir/-None-False-dir]' 'tests/unit/utils/test_utils.py::test_parse_target[file-out10-None]'
: '>>>>> End Test Output'
git checkout c989b28eae536f08767d3cb32e790187d63a581b -- tests/unit/utils/test_utils.py 2>/dev/null || true
