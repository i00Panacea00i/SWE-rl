#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 1c6f46c0419232cc45f7ae770e633d3884bac169 -- tests/func/test_version.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_version.py b/tests/func/test_version.py
--- a/tests/func/test_version.py
+++ b/tests/func/test_version.py
@@ -9,6 +9,7 @@ def test_info_in_repo(dvc_repo, caplog):
     assert re.search(re.compile(r"DVC version: \d+\.\d+\.\d+"), caplog.text)
     assert re.search(re.compile(r"Python version: \d\.\d\.\d"), caplog.text)
     assert re.search(re.compile(r"Platform: .*"), caplog.text)
+    assert re.search(re.compile(r"Binary: (True|False)"), caplog.text)
     assert re.search(
         re.compile(r"Filesystem type \(cache directory\): .*"), caplog.text
     )
@@ -26,6 +27,7 @@ def test_info_outside_of_repo(repo_dir, caplog):
     assert re.search(re.compile(r"DVC version: \d+\.\d+\.\d+"), caplog.text)
     assert re.search(re.compile(r"Python version: \d\.\d\.\d"), caplog.text)
     assert re.search(re.compile(r"Platform: .*"), caplog.text)
+    assert re.search(re.compile(r"Binary: (True|False)"), caplog.text)
     assert re.search(
         re.compile(r"Filesystem type \(workspace\): .*"), caplog.text
     )

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/func/test_version.py::test_info_outside_of_repo tests/func/test_version.py::test_info_in_repo
: '>>>>> End Test Output'
git checkout 1c6f46c0419232cc45f7ae770e633d3884bac169 -- tests/func/test_version.py 2>/dev/null || true
