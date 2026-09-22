#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 761965d260e54f8e150d8bd7ac3ab3efd6503b93 -- mypyc/test-data/run-generators.test test-data/unit/check-statements.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/mypyc/test-data/run-generators.test b/mypyc/test-data/run-generators.test
--- a/mypyc/test-data/run-generators.test
+++ b/mypyc/test-data/run-generators.test
@@ -246,12 +246,12 @@ assert run_generator(another_triple()()) == ((1,), None)
 assert run_generator(outer()) == ((0, 1, 2, 3, 4), None)
 
 [case testYieldThrow]
-from typing import Generator, Iterable, Any
+from typing import Generator, Iterable, Any, Union
 from traceback import print_tb
 from contextlib import contextmanager
 import wrapsys
 
-def generator() -> Iterable[int]:
+def generator() -> Generator[int, None, Union[int, None]]:
     try:
         yield 1
         yield 2
@@ -264,6 +264,7 @@ def generator() -> Iterable[int]:
         else:
             print('caught exception without value')
         return 0
+    return None
 
 def no_except() -> Iterable[int]:
     yield 1
@@ -355,11 +356,11 @@ with ctx_manager() as c:
     raise Exception
   File "native.py", line 10, in generator
     yield 3
-  File "native.py", line 30, in wrapper
+  File "native.py", line 31, in wrapper
     return (yield from x)
   File "native.py", line 9, in generator
     yield 2
-  File "native.py", line 30, in wrapper
+  File "native.py", line 31, in wrapper
     return (yield from x)
 caught exception without value
 caught exception with value some string
diff --git a/test-data/unit/check-statements.test b/test-data/unit/check-statements.test
--- a/test-data/unit/check-statements.test
+++ b/test-data/unit/check-statements.test
@@ -85,7 +85,7 @@ def f() -> Generator[int, None, None]:
 from typing import Iterator
 def f() -> Iterator[int]:
     yield 1
-    return "foo"
+    return "foo" # E: No return value expected
 [out]
 
 
@@ -2231,6 +2231,51 @@ class B: pass
 def foo(x: int) -> Union[Generator[A, None, None], Generator[B, None, None]]:
     yield x  # E: Incompatible types in "yield" (actual type "int", expected type "Union[A, B]")
 
+[case testYieldFromUnionOfGenerators]
+from typing import Generator, Union
+
+class T: pass
+
+def foo(arg: Union[Generator[int, None, T], Generator[str, None, T]]) -> Generator[Union[int, str], None, T]:
+    return (yield from arg)
+
+[case testYieldFromInvalidUnionReturn]
+from typing import Generator, Union
+
+class A: pass
+class B: pass
+
+def foo(arg: Union[A, B]) -> Generator[Union[int, str], None, A]:
+    return (yield from arg) # E: "yield from" can't be applied to "Union[A, B]"
+
+[case testYieldFromUnionOfGeneratorWithIterableStr]
+from typing import Generator, Union, Iterable, Optional
+
+def foo(arg: Union[Generator[int, None, bytes], Iterable[str]]) -> Generator[Union[int, str], None, Optional[bytes]]:
+    return (yield from arg)
+
+def bar(arg: Generator[str, None, str]) -> Generator[str, None, str]:
+    return foo(arg)  # E: Incompatible return value type (got "Generator[Union[int, str], None, Optional[bytes]]", expected "Generator[str, None, str]")
+
+def launder(arg: Iterable[str]) -> Generator[Union[int, str], None, Optional[bytes]]:
+    return foo(arg)
+
+def baz(arg: Generator[str, None, str]) -> Generator[Union[int, str], None, Optional[bytes]]:
+    # this is unsound, the Generator return type will actually be str
+    return launder(arg)
+[builtins fixtures/tuple.pyi]
+
+[case testYieldIteratorReturn]
+from typing import Iterator
+
+def get_strings(foo: bool) -> Iterator[str]:
+    if foo:
+        return ["foo1", "foo2"]  # E: No return value expected
+    else:
+        yield "bar1"
+        yield "bar2"
+[builtins fixtures/tuple.pyi]
+
 [case testNoCrashOnStarRightHandSide]
 x = *(1, 2, 3)  # E: can't use starred expression here
 [builtins fixtures/tuple.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-statements.test::testYieldFromUnionOfGeneratorWithIterableStr mypy/test/testcheck.py::TypeCheckSuite::check-statements.test::testYieldFromUnionOfGenerators mypy/test/testcheck.py::TypeCheckSuite::check-statements.test::testYieldIteratorReturn mypy/test/testcheck.py::TypeCheckSuite::check-statements.test::testYieldFromInvalidUnionReturn mypyc/test/test_run.py::TestRun::run-generators.test::testYieldThrow mypy/test/testcheck.py::TypeCheckSuite::check-statements.test::testNoCrashOnStarRightHandSide
: '>>>>> End Test Output'
git checkout 761965d260e54f8e150d8bd7ac3ab3efd6503b93 -- mypyc/test-data/run-generators.test test-data/unit/check-statements.test 2>/dev/null || true
