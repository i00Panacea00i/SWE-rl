#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout da7268c3af04686f70905750c5d58144f6e6d049 -- test-data/unit/stubgen.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/stubgen.test b/test-data/unit/stubgen.test
--- a/test-data/unit/stubgen.test
+++ b/test-data/unit/stubgen.test
@@ -319,6 +319,62 @@ class A:
     def f(self, x) -> None: ...
     def h(self) -> None: ...
 
+[case testFunctoolsCachedProperty]
+import functools
+
+class A:
+    @functools.cached_property
+    def x(self):
+        return 'x'
+[out]
+import functools
+
+class A:
+    @functools.cached_property
+    def x(self): ...
+
+[case testFunctoolsCachedPropertyAlias]
+import functools as ft
+
+class A:
+    @ft.cached_property
+    def x(self):
+        return 'x'
+[out]
+import functools as ft
+
+class A:
+    @ft.cached_property
+    def x(self): ...
+
+[case testCachedProperty]
+from functools import cached_property
+
+class A:
+    @cached_property
+    def x(self):
+        return 'x'
+[out]
+from functools import cached_property
+
+class A:
+    @cached_property
+    def x(self): ...
+
+[case testCachedPropertyAlias]
+from functools import cached_property as cp
+
+class A:
+    @cp
+    def x(self):
+        return 'x'
+[out]
+from functools import cached_property as cp
+
+class A:
+    @cp
+    def x(self): ...
+
 [case testStaticMethod]
 class A:
     @staticmethod

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testCachedProperty mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testFunctoolsCachedPropertyAlias mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testCachedPropertyAlias mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testFunctoolsCachedProperty mypy/test/testsemanal.py::SemAnalSuite::semanal-classes.test::testStaticMethodWithNoArgs mypy/test/testcheck.py::TypeCheckSuite::check-functools.test::testCachedProperty mypy/test/testsemanal.py::SemAnalErrorSuite::semanal-errors.test::testStaticmethodAndNonMethod mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testStaticMethod mypy/test/testtransform.py::TransformSuite::semanal-classes.test::testStaticMethod mypy/test/testcheck.py::TypeCheckSuite::check-typeguard.test::testStaticMethodTypeGuard mypy/test/testsemanal.py::SemAnalSuite::semanal-classes.test::testStaticMethod mypy/test/testtransform.py::TransformSuite::semanal-classes.test::testStaticMethodWithNoArgs
: '>>>>> End Test Output'
git checkout da7268c3af04686f70905750c5d58144f6e6d049 -- test-data/unit/stubgen.test 2>/dev/null || true
