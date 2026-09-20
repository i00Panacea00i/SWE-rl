#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8c2ef9dde8aa803e04038427ad84f09664d9d93f -- mypy/test/teststubgen.py test-data/unit/stubgen.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/mypy/test/teststubgen.py b/mypy/test/teststubgen.py
--- a/mypy/test/teststubgen.py
+++ b/mypy/test/teststubgen.py
@@ -10,6 +10,8 @@
 from types import ModuleType
 from typing import Any
 
+import pytest
+
 from mypy.errors import CompileError
 from mypy.moduleinspect import InspectError, ModuleInspect
 from mypy.stubdoc import (
@@ -698,6 +700,8 @@ def run_case_inner(self, testcase: DataDrivenTestCase) -> None:
                 f.write(content)
 
         options = self.parse_flags(source, extra)
+        if sys.version_info < options.pyversion:
+            pytest.skip()
         modules = self.parse_modules(source)
         out_dir = "out"
         try:
diff --git a/test-data/unit/stubgen.test b/test-data/unit/stubgen.test
--- a/test-data/unit/stubgen.test
+++ b/test-data/unit/stubgen.test
@@ -1211,6 +1211,56 @@ T = TypeVar('T')
 
 class D(Generic[T]): ...
 
+[case testGenericClassTypeVarTuple]
+from typing import Generic
+from typing_extensions import TypeVarTuple, Unpack
+Ts = TypeVarTuple('Ts')
+class D(Generic[Unpack[Ts]]): ...
+[out]
+from typing import Generic
+from typing_extensions import TypeVarTuple, Unpack
+
+Ts = TypeVarTuple('Ts')
+
+class D(Generic[Unpack[Ts]]): ...
+
+[case testGenericClassTypeVarTuple_semanal]
+from typing import Generic
+from typing_extensions import TypeVarTuple, Unpack
+Ts = TypeVarTuple('Ts')
+class D(Generic[Unpack[Ts]]): ...
+[out]
+from typing import Generic
+from typing_extensions import TypeVarTuple, Unpack
+
+Ts = TypeVarTuple('Ts')
+
+class D(Generic[Unpack[Ts]]): ...
+
+[case testGenericClassTypeVarTuplePy311]
+# flags: --python-version=3.11
+from typing import Generic, TypeVarTuple
+Ts = TypeVarTuple('Ts')
+class D(Generic[*Ts]): ...
+[out]
+from typing import Generic, TypeVarTuple
+
+Ts = TypeVarTuple('Ts')
+
+class D(Generic[*Ts]): ...
+
+[case testGenericClassTypeVarTuplePy311_semanal]
+# flags: --python-version=3.11
+from typing import Generic, TypeVarTuple
+Ts = TypeVarTuple('Ts')
+class D(Generic[*Ts]): ...
+[out]
+from typing import Generic, TypeVarTuple
+
+Ts = TypeVarTuple('Ts')
+
+class D(Generic[*Ts]): ...
+
 [case testObjectBaseClass]
 class A(object): ...
 [out]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testGenericClassTypeVarTuplePy311 mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testGenericClassTypeVarTuplePy311_semanal mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testGenericClassTypeVarTuple mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testObjectBaseClass mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testGenericClassTypeVarTuple_semanal mypy/test/teststubgen.py::StubgenPythonSuite::stubgen.test::testObjectBaseClassWithImport
: '>>>>> End Test Output'
git checkout 8c2ef9dde8aa803e04038427ad84f09664d9d93f -- mypy/test/teststubgen.py test-data/unit/stubgen.test 2>/dev/null || true
