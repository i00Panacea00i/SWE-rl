#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 43a605f742bd554acbdff9bea74c764621e3aa44 -- test-data/unit/check-unreachable-code.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-unreachable-code.test b/test-data/unit/check-unreachable-code.test
--- a/test-data/unit/check-unreachable-code.test
+++ b/test-data/unit/check-unreachable-code.test
@@ -1494,3 +1494,23 @@ from typing import Generator
 def f() -> Generator[None, None, None]:
     return None
     yield None
+
+[case testLambdaNoReturn]
+# flags: --warn-unreachable
+from typing import Callable, NoReturn
+
+def foo() -> NoReturn:
+    raise
+
+f = lambda: foo()
+x = 0  # not unreachable
+
+[case testLambdaNoReturnAnnotated]
+# flags: --warn-unreachable
+from typing import Callable, NoReturn
+
+def foo() -> NoReturn:
+    raise
+
+f: Callable[[], NoReturn] = lambda: foo()  # E: Return statement in function which does not return # (false positive: https://github.com/python/mypy/issues/17254)
+x = 0  # not unreachable

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-unreachable-code.test::testLambdaNoReturn mypy/test/testcheck.py::TypeCheckSuite::check-unreachable-code.test::testLambdaNoReturnAnnotated
: '>>>>> End Test Output'
git checkout 43a605f742bd554acbdff9bea74c764621e3aa44 -- test-data/unit/check-unreachable-code.test 2>/dev/null || true
