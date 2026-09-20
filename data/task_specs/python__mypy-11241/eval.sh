#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout ed0cc78a5cbdfcb9724cf1f294f7b5cbbd1d6778 -- test-data/unit/check-fastparse.test test-data/unit/parse.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-fastparse.test b/test-data/unit/check-fastparse.test
--- a/test-data/unit/check-fastparse.test
+++ b/test-data/unit/check-fastparse.test
@@ -322,7 +322,7 @@ x @= 1
 from typing import Dict
 x = None # type: Dict[x: y]
 [out]
-main:3: error: syntax error in type comment
+main:3: error: Slice usage in type annotation is invalid
 
 [case testPrintStatementTrailingCommaFastParser_python2]
 
diff --git a/test-data/unit/parse.test b/test-data/unit/parse.test
--- a/test-data/unit/parse.test
+++ b/test-data/unit/parse.test
@@ -949,6 +949,88 @@ main:1: error: invalid syntax
 [out version>=3.10]
 main:1: error: invalid syntax. Perhaps you forgot a comma?
 
+[case testSliceInAnnotation39]
+# flags: --python-version 3.9
+a: Annotated[int, 1:2]  # E: Slice usage in type annotation is invalid
+b: Dict[int, x:y]  # E: Slice usage in type annotation is invalid
+c: Dict[x:y]  # E: Slice usage in type annotation is invalid
+[out]
+
+[case testSliceInAnnotation38]
+# flags: --python-version 3.8
+a: Annotated[int, 1:2]  # E: Slice usage in type annotation is invalid
+b: Dict[int, x:y]  # E: Slice usage in type annotation is invalid
+c: Dict[x:y]  # E: Slice usage in type annotation is invalid
+[out]
+
+[case testSliceInAnnotationTypeComment39]
+# flags: --python-version 3.9
+a = None  # type: Annotated[int, 1:2]  # E: Slice usage in type annotation is invalid
+b = None  # type: Dict[int, x:y]  # E: Slice usage in type annotation is invalid
+c = None  # type: Dict[x:y]  # E: Slice usage in type annotation is invalid
+[out]
+
+[case testCorrectSlicesInAnnotations39]
+# flags: --python-version 3.9
+a: Annotated[int, slice(1, 2)]
+b: Dict[int, {x:y}]
+c: Dict[{x:y}]
+[out]
+MypyFile:1(
+  AssignmentStmt:2(
+    NameExpr(a)
+    TempNode:2(
+      Any)
+    Annotated?[int?, None])
+  AssignmentStmt:3(
+    NameExpr(b)
+    TempNode:3(
+      Any)
+    Dict?[int?, None])
+  AssignmentStmt:4(
+    NameExpr(c)
+    TempNode:4(
+      Any)
+    Dict?[None]))
+
+[case testCorrectSlicesInAnnotations38]
+# flags: --python-version 3.8
+a: Annotated[int, slice(1, 2)]
+b: Dict[int, {x:y}]
+c: Dict[{x:y}]
+[out]
+MypyFile:1(
+  AssignmentStmt:2(
+    NameExpr(a)
+    TempNode:2(
+      Any)
+    Annotated?[int?, None])
+  AssignmentStmt:3(
+    NameExpr(b)
+    TempNode:3(
+      Any)
+    Dict?[int?, None])
+  AssignmentStmt:4(
+    NameExpr(c)
+    TempNode:4(
+      Any)
+    Dict?[None]))
+
+[case testSliceInList39]
+# flags: --python-version 3.9
+x = [1, 2][1:2]
+[out]
+MypyFile:1(
+  AssignmentStmt:2(
+    NameExpr(x)
+    IndexExpr:2(
+      ListExpr:2(
+        IntExpr(1)
+        IntExpr(2))
+      SliceExpr:2(
+        IntExpr(1)
+        IntExpr(2)))))
+
 [case testDictionaryExpression]
 {}
 {1:x}

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testparse.py::ParserSuite::testSliceInAnnotation39 mypy/test/testparse.py::ParserSuite::testSliceInAnnotationTypeComment39 mypy/test/testparse.py::ParserSuite::testSliceInAnnotation38 mypy/test/testparse.py::ParserSuite::testDictionaryExpression mypy/test/testparse.py::ParserSuite::testCorrectSlicesInAnnotations39 mypy/test/testparse.py::ParserSuite::testCorrectSlicesInAnnotations38 mypy/test/testcheck.py::TypeCheckSuite::testPrintStatementTrailingCommaFastParser_python2 mypy/test/testparse.py::ParserSuite::testSliceInList39
: '>>>>> End Test Output'
git checkout ed0cc78a5cbdfcb9724cf1f294f7b5cbbd1d6778 -- test-data/unit/check-fastparse.test test-data/unit/parse.test 2>/dev/null || true
