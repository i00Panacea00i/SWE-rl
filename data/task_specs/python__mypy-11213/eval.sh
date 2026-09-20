#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8e82171a3e68a5180fab267cad4d2b7cfa1f5cdc -- mypy/test/testsemanal.py test-data/unit/check-expressions.test test-data/unit/semanal-lambda.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/mypy/test/testsemanal.py b/mypy/test/testsemanal.py
--- a/mypy/test/testsemanal.py
+++ b/mypy/test/testsemanal.py
@@ -32,7 +32,8 @@
                  'semanal-typeddict.test',
                  'semenal-literal.test',
                  'semanal-classvar.test',
-                 'semanal-python2.test']
+                 'semanal-python2.test',
+                 'semanal-lambda.test']
 
 
 def get_semanal_options(program_text: str, testcase: DataDrivenTestCase) -> Options:
diff --git a/test-data/unit/check-expressions.test b/test-data/unit/check-expressions.test
--- a/test-data/unit/check-expressions.test
+++ b/test-data/unit/check-expressions.test
@@ -2366,6 +2366,19 @@ def f() -> None:
 [out]
 main:3: note: Revealed type is "builtins.int"
 
+[case testLambdaTypedContext]
+def f() -> None:
+    lambda: 'a'.missing()  # E: "str" has no attribute "missing"
+
+[case testLambdaUnypedContext]
+def f():
+    lambda: 'a'.missing()
+
+[case testLambdaCheckUnypedContext]
+# flags: --check-untyped-defs
+def f():
+    lambda: 'a'.missing()  # E: "str" has no attribute "missing"
+
 [case testEqNone]
 None == None
 [builtins fixtures/ops.pyi]
diff --git a/test-data/unit/semanal-lambda.test b/test-data/unit/semanal-lambda.test
new file mode 100644
--- /dev/null
+++ b/test-data/unit/semanal-lambda.test
@@ -0,0 +1,94 @@
+[case testLambdaInheritsCheckedContextFromFunc]
+def g():
+    return lambda x: UNDEFINED in x
+[out]
+MypyFile:1(
+  FuncDef:1(
+    g
+    Block:1(
+      ReturnStmt:2(
+        LambdaExpr:2(
+          Args(
+            Var(x))
+          Block:2(
+            ReturnStmt:2(
+              ComparisonExpr:2(
+                in
+                NameExpr(UNDEFINED)
+                NameExpr(x [l])))))))))
+
+[case testLambdaInheritsCheckedContextFromFuncForced]
+# flags: --check-untyped-defs
+def g():
+    return lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromTypedFunc]
+def g() -> None:
+    return lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromTypedFuncForced]
+# flags: --check-untyped-defs
+def g() -> None:
+    return lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromModule]
+g = lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromModuleForce]
+# flags: --check-untyped-defs
+g = lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromModuleLambdaStack]
+g = lambda: lambda: lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromModuleLambdaStackForce]
+# flags: --check-untyped-defs
+g = lambda: lambda: lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromFuncLambdaStack]
+def g():
+    return lambda: lambda: lambda x: UNDEFINED in x
+[out]
+MypyFile:1(
+  FuncDef:1(
+    g
+    Block:1(
+      ReturnStmt:2(
+        LambdaExpr:2(
+          Block:2(
+            ReturnStmt:2(
+              LambdaExpr:2(
+                Block:2(
+                  ReturnStmt:2(
+                    LambdaExpr:2(
+                      Args(
+                        Var(x))
+                      Block:2(
+                        ReturnStmt:2(
+                          ComparisonExpr:2(
+                            in
+                            NameExpr(UNDEFINED)
+                            NameExpr(x [l])))))))))))))))
+
+[case testLambdaInheritsCheckedContextFromFuncLambdaStackForce]
+# flags: --check-untyped-defs
+def g():
+    return lambda: lambda: lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromTypedFuncLambdaStack]
+def g() -> None:
+    return lambda: lambda: lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromTypedFuncLambdaStackForce]
+# flags: --check-untyped-defs
+def g() -> None:
+    return lambda: lambda: lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromClassLambdaStack]
+class A:
+    g = lambda: lambda: lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined
+
+[case testLambdaInheritsCheckedContextFromClassLambdaStackForce]
+# flags: --check-untyped-defs
+class A:
+    g = lambda: lambda: lambda x: UNDEFINED in x  # E: Name "UNDEFINED" is not defined

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromFuncLambdaStack mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromFunc mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromClassLambdaStackForce mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromModuleForce mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromFuncLambdaStackForce mypy/test/testcheck.py::TypeCheckSuite::testLambdaTypedContext mypy/test/testcheck.py::TypeCheckSuite::testEqNone mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromModule mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromTypedFunc mypy/test/testcheck.py::TypeCheckSuite::testLambdaUnypedContext mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromTypedFuncForced mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromModuleLambdaStackForce mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromFuncForced mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromModuleLambdaStack mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromTypedFuncLambdaStackForce mypy/test/testcheck.py::TypeCheckSuite::testLambdaCheckUnypedContext mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromClassLambdaStack mypy/test/testsemanal.py::SemAnalSuite::testLambdaInheritsCheckedContextFromTypedFuncLambdaStack
: '>>>>> End Test Output'
git checkout 8e82171a3e68a5180fab267cad4d2b7cfa1f5cdc -- mypy/test/testsemanal.py test-data/unit/check-expressions.test test-data/unit/semanal-lambda.test 2>/dev/null || true
