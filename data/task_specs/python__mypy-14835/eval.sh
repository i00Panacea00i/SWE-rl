#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e21ddbf3ebe80bc219708a5f69a1b7d0b4e20400 -- test-data/unit/daemon.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/daemon.test b/test-data/unit/daemon.test
--- a/test-data/unit/daemon.test
+++ b/test-data/unit/daemon.test
@@ -522,3 +522,92 @@ class A:
     x: int
 class B:
     x: int
+
+[case testUnusedTypeIgnorePreservedOnRerun]
+-- Regression test for https://github.com/python/mypy/issues/9655
+$ dmypy start -- --warn-unused-ignores --no-error-summary
+Daemon started
+$ dmypy check -- bar.py
+bar.py:2: error: Unused "type: ignore" comment
+== Return code: 1
+$ dmypy check -- bar.py
+bar.py:2: error: Unused "type: ignore" comment
+== Return code: 1
+
+[file foo/__init__.py]
+[file foo/empty.py]
+[file bar.py]
+from foo.empty import *
+a = 1  # type: ignore
+
+[case testTypeIgnoreWithoutCodePreservedOnRerun]
+-- Regression test for https://github.com/python/mypy/issues/9655
+$ dmypy start -- --enable-error-code ignore-without-code --no-error-summary
+Daemon started
+$ dmypy check -- bar.py
+bar.py:2: error: "type: ignore" comment without error code  [ignore-without-code]
+== Return code: 1
+$ dmypy check -- bar.py
+bar.py:2: error: "type: ignore" comment without error code  [ignore-without-code]
+== Return code: 1
+
+[file foo/__init__.py]
+[file foo/empty.py]
+[file bar.py]
+from foo.empty import *
+a = 1  # type: ignore
+
+[case testUnusedTypeIgnorePreservedAfterChange]
+-- Regression test for https://github.com/python/mypy/issues/9655
+$ dmypy start -- --warn-unused-ignores --no-error-summary
+Daemon started
+$ dmypy check -- bar.py
+bar.py:2: error: Unused "type: ignore" comment
+== Return code: 1
+$ {python} -c "print('\n')" >> bar.py
+$ dmypy check -- bar.py
+bar.py:2: error: Unused "type: ignore" comment
+== Return code: 1
+
+[file foo/__init__.py]
+[file foo/empty.py]
+[file bar.py]
+from foo.empty import *
+a = 1  # type: ignore
+
+[case testTypeIgnoreWithoutCodePreservedAfterChange]
+-- Regression test for https://github.com/python/mypy/issues/9655
+$ dmypy start -- --enable-error-code ignore-without-code --no-error-summary
+Daemon started
+$ dmypy check -- bar.py
+bar.py:2: error: "type: ignore" comment without error code  [ignore-without-code]
+== Return code: 1
+$ {python} -c "print('\n')" >> bar.py
+$ dmypy check -- bar.py
+bar.py:2: error: "type: ignore" comment without error code  [ignore-without-code]
+== Return code: 1
+
+[file foo/__init__.py]
+[file foo/empty.py]
+[file bar.py]
+from foo.empty import *
+a = 1  # type: ignore
+
+[case testPossiblyUndefinedVarsPreservedAfterUpdate]
+-- Regression test for https://github.com/python/mypy/issues/9655
+$ dmypy start -- --enable-error-code possibly-undefined --no-error-summary
+Daemon started
+$ dmypy check -- bar.py
+bar.py:4: error: Name "a" may be undefined  [possibly-undefined]
+== Return code: 1
+$ dmypy check -- bar.py
+bar.py:4: error: Name "a" may be undefined  [possibly-undefined]
+== Return code: 1
+
+[file foo/__init__.py]
+[file foo/empty.py]
+[file bar.py]
+from foo.empty import *
+if False:
+    a = 1
+a

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testdaemon.py::DaemonSuite::daemon.test::testUnusedTypeIgnorePreservedOnRerun mypy/test/testdaemon.py::DaemonSuite::daemon.test::testTypeIgnoreWithoutCodePreservedOnRerun mypy/test/testdaemon.py::DaemonSuite::daemon.test::testTypeIgnoreWithoutCodePreservedAfterChange mypy/test/testdaemon.py::DaemonSuite::daemon.test::testUnusedTypeIgnorePreservedAfterChange mypy/test/testdaemon.py::DaemonSuite::daemon.test::testPossiblyUndefinedVarsPreservedAfterUpdate
: '>>>>> End Test Output'
git checkout e21ddbf3ebe80bc219708a5f69a1b7d0b4e20400 -- test-data/unit/daemon.test 2>/dev/null || true
