#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 28d57b13ab5ea765728bde534eda2877f8d92b4b -- test-data/unit/check-classes.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-classes.test b/test-data/unit/check-classes.test
--- a/test-data/unit/check-classes.test
+++ b/test-data/unit/check-classes.test
@@ -6419,6 +6419,37 @@ class B(A):
 
 reveal_type(B())  # N: Revealed type is "__main__.B"
 
+[case testNewReturnType10]
+# https://github.com/python/mypy/issues/11398
+from typing import Type
+
+class MyMetaClass(type):
+    def __new__(cls, name, bases, attrs) -> Type['MyClass']:
+        pass
+
+class MyClass(metaclass=MyMetaClass):
+    pass
+
+[case testNewReturnType11]
+# https://github.com/python/mypy/issues/11398
+class MyMetaClass(type):
+    def __new__(cls, name, bases, attrs) -> type:
+        pass
+
+class MyClass(metaclass=MyMetaClass):
+    pass
+
+[case testNewReturnType12]
+# https://github.com/python/mypy/issues/11398
+from typing import Type
+
+class MyMetaClass(type):
+    def __new__(cls, name, bases, attrs) -> int:  # E: Incompatible return type for "__new__" (returns "int", but must return a subtype of "type")
+        pass
+
+class MyClass(metaclass=MyMetaClass):
+    pass
+
 [case testGenericOverride]
 from typing import Generic, TypeVar, Any
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testNewReturnType10 mypy/test/testcheck.py::TypeCheckSuite::testNewReturnType11 mypy/test/testcheck.py::TypeCheckSuite::testNewReturnType12 mypy/test/testcheck.py::TypeCheckSuite::testGenericOverridePreciseValid mypy/test/testcheck.py::TypeCheckSuite::testGenericOverridePreciseInvalid mypy/test/testcheck.py::TypeCheckSuite::testGenericOverride mypy/test/testcheck.py::TypeCheckSuite::testGenericOverrideGenericChained mypy/test/testcheck.py::TypeCheckSuite::testGenericOverrideGeneric
: '>>>>> End Test Output'
git checkout 28d57b13ab5ea765728bde534eda2877f8d92b4b -- test-data/unit/check-classes.test 2>/dev/null || true
