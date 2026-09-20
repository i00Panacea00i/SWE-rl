#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout ff81a1c7abc91d9984fc73b9f2b9eab198001c8e -- test-data/unit/stubgen.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/stubgen.test b/test-data/unit/stubgen.test
--- a/test-data/unit/stubgen.test
+++ b/test-data/unit/stubgen.test
@@ -2772,9 +2772,9 @@ y: b.Y
 z: p.a.X
 
 [out]
+import p.a
 import p.a as a
 import p.b as b
-import p.a
 
 x: a.X
 y: b.Y
@@ -2787,7 +2787,7 @@ from p import a
 x: a.X
 
 [out]
-from p import a as a
+from p import a
 
 x: a.X
 
@@ -2809,7 +2809,7 @@ from p import a
 x: a.X
 
 [out]
-from p import a as a
+from p import a
 
 x: a.X
 
@@ -2859,6 +2859,60 @@ import p.a
 x: a.X
 y: p.a.Y
 
+[case testNestedImports]
+import p
+import p.m1
+import p.m2
+
+x: p.X
+y: p.m1.Y
+z: p.m2.Z
+
+[out]
+import p
+import p.m1
+import p.m2
+
+x: p.X
+y: p.m1.Y
+z: p.m2.Z
+
+[case testNestedImportsAliased]
+import p as t
+import p.m1 as pm1
+import p.m2 as pm2
+
+x: t.X
+y: pm1.Y
+z: pm2.Z
+
+[out]
+import p as t
+import p.m1 as pm1
+import p.m2 as pm2
+
+x: t.X
+y: pm1.Y
+z: pm2.Z
+
+[case testNestedFromImports]
+from p import m1
+from p.m1 import sm1
+from p.m2 import sm2
+
+x: m1.X
+y: sm1.Y
+z: sm2.Z
+
+[out]
+from p import m1
+from p.m1 import sm1
+from p.m2 import sm2
+
+x: m1.X
+y: sm1.Y
+z: sm2.Z
+
 [case testOverload_fromTypingImport]
 from typing import Tuple, Union, overload
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testNestedFromImports mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testNestedImports mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testNestedImportsAliased mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testOverload_fromTypingImport
: '>>>>> End Test Output'
git checkout ff81a1c7abc91d9984fc73b9f2b9eab198001c8e -- test-data/unit/stubgen.test 2>/dev/null || true
