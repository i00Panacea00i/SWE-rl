#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 35dd1fda9cfb4b645ae431f4621f2d1853d4fb7c -- tests/unit/test_updater.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/unit/test_updater.py b/tests/unit/test_updater.py
--- a/tests/unit/test_updater.py
+++ b/tests/unit/test_updater.py
@@ -44,6 +44,28 @@ def test_fetch(mock_get, updater):
     assert info["version"] == __version__
 
 
+@pytest.mark.parametrize(
+    "core, result",
+    [
+        ({}, True),
+        ({"check_update": "true"}, True),
+        ({"check_update": "false"}, False),
+    ],
+)
+def test_is_enabled(dvc, updater, core, result):
+    with dvc.config.edit("local") as conf:
+        conf["core"] = core
+    assert result == updater.is_enabled()
+
+
+@pytest.mark.parametrize("result", [True, False])
+@mock.patch("dvc.updater.Updater._check")
+def test_check_update_respect_config(mock_check, result, updater, mocker):
+    mocker.patch.object(updater, "is_enabled", return_value=result)
+    updater.check()
+    assert result == mock_check.called
+
+
 @pytest.mark.parametrize(
     "current,latest,notify",
     [

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/unit/test_updater.py::test_is_enabled[core2-False]' 'tests/unit/test_updater.py::test_check_update_respect_config[False]' 'tests/unit/test_updater.py::test_is_enabled[core1-True]' 'tests/unit/test_updater.py::test_is_enabled[core0-True]' 'tests/unit/test_updater.py::test_check_update_respect_config[True]' tests/unit/test_updater.py::test_fetch 'tests/unit/test_updater.py::test_check_updates[uptodate]' 'tests/unit/test_updater.py::test_check_updates[ahead]' tests/unit/test_updater.py::test_check tests/unit/test_updater.py::test_check_fetches_on_invalid_data_format 'tests/unit/test_updater.py::test_check_updates[behind]' tests/unit/test_updater.py::test_check_refetches_each_day
: '>>>>> End Test Output'
git checkout 35dd1fda9cfb4b645ae431f4621f2d1853d4fb7c -- tests/unit/test_updater.py 2>/dev/null || true
