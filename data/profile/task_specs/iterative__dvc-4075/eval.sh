#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout a2f1367a9a75849ef6ad7ee23a5bacc18580f102 -- tests/func/test_import_url.py tests/unit/command/test_imp_url.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/func/test_import_url.py b/tests/func/test_import_url.py
--- a/tests/func/test_import_url.py
+++ b/tests/func/test_import_url.py
@@ -103,3 +103,12 @@ def test_import_stage_accompanies_target(tmp_dir, dvc, erepo_dir):
 def test_import_url_nonexistent(dvc, erepo_dir):
     with pytest.raises(DependencyDoesNotExistError):
         dvc.imp_url(os.fspath(erepo_dir / "non-existent"))
+
+
+def test_import_url_with_no_exec(tmp_dir, dvc, erepo_dir):
+    tmp_dir.gen({"data_dir": {"file": "file content"}})
+    src = os.path.join("data_dir", "file")
+
+    dvc.imp_url(src, ".", no_exec=True)
+    dst = tmp_dir / "file"
+    assert not dst.exists()
diff --git a/tests/unit/command/test_imp_url.py b/tests/unit/command/test_imp_url.py
--- a/tests/unit/command/test_imp_url.py
+++ b/tests/unit/command/test_imp_url.py
@@ -14,7 +14,7 @@ def test_import_url(mocker):
 
     assert cmd.run() == 0
 
-    m.assert_called_once_with("src", out="out", fname="file")
+    m.assert_called_once_with("src", out="out", fname="file", no_exec=False)
 
 
 def test_failed_import_url(mocker, caplog):
@@ -31,3 +31,16 @@ def test_failed_import_url(mocker, caplog):
             "adding it with `dvc add`."
         )
         assert expected_error in caplog.text
+
+
+def test_import_url_no_exec(mocker):
+    cli_args = parse_args(
+        ["import-url", "--no-exec", "src", "out", "--file", "file"]
+    )
+
+    cmd = cli_args.func(cli_args)
+    m = mocker.patch.object(cmd.repo, "imp_url", autospec=True)
+
+    assert cmd.run() == 0
+
+    m.assert_called_once_with("src", out="out", fname="file", no_exec=True)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/unit/command/test_imp_url.py::test_import_url_no_exec tests/unit/command/test_imp_url.py::test_import_url tests/unit/command/test_imp_url.py::test_failed_import_url tests/func/test_import_url.py::TestCmdImport::test_unsupported
: '>>>>> End Test Output'
git checkout a2f1367a9a75849ef6ad7ee23a5bacc18580f102 -- tests/func/test_import_url.py tests/unit/command/test_imp_url.py 2>/dev/null || true
