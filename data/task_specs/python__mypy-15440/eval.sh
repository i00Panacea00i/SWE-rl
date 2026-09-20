#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e14cddbe31c9437502acef022dca376a25d0b50d -- test-data/unit/daemon.test test-data/unit/fine-grained.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/daemon.test b/test-data/unit/daemon.test
--- a/test-data/unit/daemon.test
+++ b/test-data/unit/daemon.test
@@ -62,6 +62,28 @@ Daemon started
 \[mypy]
 files = ./foo.py
 
+[case testDaemonRunMultipleStrict]
+$ dmypy run -- foo.py --strict --follow-imports=error
+Daemon started
+foo.py:1: error: Function is missing a return type annotation
+foo.py:1: note: Use "-> None" if function does not return a value
+Found 1 error in 1 file (checked 1 source file)
+== Return code: 1
+$ dmypy run -- bar.py --strict --follow-imports=error
+bar.py:1: error: Function is missing a return type annotation
+bar.py:1: note: Use "-> None" if function does not return a value
+Found 1 error in 1 file (checked 1 source file)
+== Return code: 1
+$ dmypy run -- foo.py --strict --follow-imports=error
+foo.py:1: error: Function is missing a return type annotation
+foo.py:1: note: Use "-> None" if function does not return a value
+Found 1 error in 1 file (checked 1 source file)
+== Return code: 1
+[file foo.py]
+def f(): pass
+[file bar.py]
+def f(): pass
+
 [case testDaemonRunRestart]
 $ dmypy run -- foo.py --follow-imports=error
 Daemon started
diff --git a/test-data/unit/fine-grained.test b/test-data/unit/fine-grained.test
--- a/test-data/unit/fine-grained.test
+++ b/test-data/unit/fine-grained.test
@@ -10340,3 +10340,24 @@ reveal_type(x)
 [out]
 ==
 a.py:3: note: Revealed type is "Union[def (x: builtins.int) -> builtins.int, def (*x: builtins.int) -> builtins.int]"
+
+[case testErrorInReAddedModule]
+# flags: --disallow-untyped-defs --follow-imports=error
+# cmd: mypy a.py
+# cmd2: mypy b.py
+# cmd3: mypy a.py
+
+[file a.py]
+def f(): pass
+[file b.py]
+def f(): pass
+[file unrelated.txt.3]
+[out]
+a.py:1: error: Function is missing a return type annotation
+a.py:1: note: Use "-> None" if function does not return a value
+==
+b.py:1: error: Function is missing a return type annotation
+b.py:1: note: Use "-> None" if function does not return a value
+==
+a.py:1: error: Function is missing a return type annotation
+a.py:1: note: Use "-> None" if function does not return a value

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testfinegrained.py::FineGrainedSuite::fine-grained.test::testErrorInReAddedModule mypy/test/testdaemon.py::DaemonSuite::daemon.test::testDaemonRunMultipleStrict mypy/test/testdaemon.py::DaemonSuite::daemon.test::testDaemonRunRestartPretty mypy/test/testdaemon.py::DaemonSuite::daemon.test::testDaemonRunRestart mypy/test/testdaemon.py::DaemonSuite::daemon.test::testDaemonRunRestartGlobs mypy/test/testdaemon.py::DaemonSuite::daemon.test::testDaemonRunRestartPluginVersion
: '>>>>> End Test Output'
git checkout e14cddbe31c9437502acef022dca376a25d0b50d -- test-data/unit/daemon.test test-data/unit/fine-grained.test 2>/dev/null || true
