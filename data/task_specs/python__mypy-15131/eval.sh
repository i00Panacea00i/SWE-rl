#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 00f3913b314994b4b391a2813a839c094482b632 -- test-data/unit/check-modules.test test-data/unit/check-python311.test test-data/unit/check-statements.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-modules.test b/test-data/unit/check-modules.test
--- a/test-data/unit/check-modules.test
+++ b/test-data/unit/check-modules.test
@@ -39,7 +39,7 @@ try:
     pass
 except m.Err:
     pass
-except m.Bad: # E: Exception type must be derived from BaseException
+except m.Bad: # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     pass
 [file m.py]
 class Err(BaseException): pass
@@ -53,7 +53,7 @@ try:
     pass
 except Err:
     pass
-except Bad: # E: Exception type must be derived from BaseException
+except Bad: # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     pass
 [file m.py]
 class Err(BaseException): pass
diff --git a/test-data/unit/check-python311.test b/test-data/unit/check-python311.test
--- a/test-data/unit/check-python311.test
+++ b/test-data/unit/check-python311.test
@@ -34,7 +34,7 @@ except* (RuntimeError, Custom) as e:
 class Bad: ...
 try:
     pass
-except* (RuntimeError, Bad) as e:  # E: Exception type must be derived from BaseException
+except* (RuntimeError, Bad) as e:  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     reveal_type(e)  # N: Revealed type is "builtins.ExceptionGroup[Any]"
 [builtins fixtures/exception.pyi]
 
diff --git a/test-data/unit/check-statements.test b/test-data/unit/check-statements.test
--- a/test-data/unit/check-statements.test
+++ b/test-data/unit/check-statements.test
@@ -659,9 +659,9 @@ class E2(E1): pass
 try:
     pass
 except (E1, E2): pass
-except (E1, object): pass # E: Exception type must be derived from BaseException
-except (object, E2): pass # E: Exception type must be derived from BaseException
-except (E1, (E2,)): pass  # E: Exception type must be derived from BaseException
+except (E1, object): pass # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
+except (object, E2): pass # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
+except (E1, (E2,)): pass  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
 
 except (E1, E2): pass
 except ((E1, E2)): pass
@@ -690,7 +690,7 @@ except (E1, E2) as e1:
 except (E2, E1) as e2:
     a = e2 # type: E1
     b = e2 # type: E2 # E: Incompatible types in assignment (expression has type "E1", variable has type "E2")
-except (E1, E2, int) as e3: # E: Exception type must be derived from BaseException
+except (E1, E2, int) as e3: # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     pass
 [builtins fixtures/exception.pyi]
 
@@ -750,13 +750,13 @@ def nested_union(exc: Union[Type[E1], Union[Type[E2], Type[E3]]]) -> None:
 def error_in_union(exc: Union[Type[E1], int]) -> None:
     try:
         pass
-    except exc as e:  # E: Exception type must be derived from BaseException
+    except exc as e:  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
         pass
 
 def error_in_variadic(exc: Tuple[int, ...]) -> None:
     try:
         pass
-    except exc as e:  # E: Exception type must be derived from BaseException
+    except exc as e:  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
         pass
 
 [builtins fixtures/tuple.pyi]
@@ -784,15 +784,15 @@ except E1 as e1:
     reveal_type(e1)  # N: Revealed type is "Any"
 except E2 as e2:
     reveal_type(e2)  # N: Revealed type is "__main__.E2"
-except NotBaseDerived as e3:  # E: Exception type must be derived from BaseException
+except NotBaseDerived as e3:  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     pass
-except (NotBaseDerived, E1) as e4:  # E: Exception type must be derived from BaseException
+except (NotBaseDerived, E1) as e4:  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     pass
-except (NotBaseDerived, E2) as e5:  # E: Exception type must be derived from BaseException
+except (NotBaseDerived, E2) as e5:  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     pass
-except (NotBaseDerived, E1, E2) as e6:  # E: Exception type must be derived from BaseException
+except (NotBaseDerived, E1, E2) as e6:  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     pass
-except (E1, E2, NotBaseDerived) as e6:  # E: Exception type must be derived from BaseException
+except (E1, E2, NotBaseDerived) as e6:  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
     pass
 [builtins fixtures/exception.pyi]
 
@@ -953,8 +953,8 @@ except a as b:
 import typing
 def exc() -> BaseException: pass
 try: pass
-except exc as e: pass             # E: Exception type must be derived from BaseException
-except BaseException() as b: pass # E: Exception type must be derived from BaseException
+except exc as e: pass             # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
+except BaseException() as b: pass # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
 [builtins fixtures/exception.pyi]
 
 [case testTupleValueAsExceptionType]
@@ -980,7 +980,7 @@ except exs2 as e2:
 
 exs3 = (E1, (E1_1, (E1_2,)))
 try: pass
-except exs3 as e3: pass  # E: Exception type must be derived from BaseException
+except exs3 as e3: pass  # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
 [builtins fixtures/exception.pyi]
 
 [case testInvalidTupleValueAsExceptionType]
@@ -991,7 +991,7 @@ class E2(E1): pass
 
 exs1 = (E1, E2, int)
 try: pass
-except exs1 as e: pass # E: Exception type must be derived from BaseException
+except exs1 as e: pass # E: Exception type must be derived from BaseException (or be a tuple of exception classes)
 [builtins fixtures/exception.pyi]
 
 [case testOverloadedExceptionType]
@@ -1034,7 +1034,7 @@ def h(e: Type[int]):
 [builtins fixtures/exception.pyi]
 [out]
 main:9: note: Revealed type is "builtins.BaseException"
-main:12: error: Exception type must be derived from BaseException
+main:12: error: Exception type must be derived from BaseException (or be a tuple of exception classes)
 
 
 -- Del statement

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-statements.test::testInvalidTupleValueAsExceptionType mypy/test/testcheck.py::TypeCheckSuite::check-statements.test::testTupleValueAsExceptionType mypy/test/testcheck.py::TypeCheckSuite::check-statements.test::testOverloadedExceptionType
: '>>>>> End Test Output'
git checkout 00f3913b314994b4b391a2813a839c094482b632 -- test-data/unit/check-modules.test test-data/unit/check-python311.test test-data/unit/check-statements.test 2>/dev/null || true
