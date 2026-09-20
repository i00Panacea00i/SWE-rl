#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 5005428f6bf143d4f8d75b7cb9dd258d00e8ef14 -- test-data/unit/check-selftype.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-selftype.test b/test-data/unit/check-selftype.test
--- a/test-data/unit/check-selftype.test
+++ b/test-data/unit/check-selftype.test
@@ -232,7 +232,7 @@ class C(A[None]):
                                      # N:          def f(self, s: int) -> int
 [builtins fixtures/tuple.pyi]
 
-[case testSelfTypeOverrideCompatibilityTypeVar-xfail]
+[case testSelfTypeOverrideCompatibilityTypeVar]
 from typing import overload, TypeVar, Union
 
 AT = TypeVar("AT", bound="A")
@@ -266,6 +266,26 @@ class B(A):
     def f(*a, **kw): ...
 [builtins fixtures/dict.pyi]
 
+[case testSelfTypeOverrideCompatibilitySelfTypeVar]
+from typing import Any, Generic, Self, TypeVar, overload
+
+T_co = TypeVar('T_co', covariant=True)
+
+class Config(Generic[T_co]):
+	@overload
+	def get(self, instance: None) -> Self: ...
+	@overload
+	def get(self, instance: Any) -> T_co: ...
+	def get(self, *a, **kw): ...
+
+class MultiConfig(Config[T_co]):
+	@overload
+	def get(self, instance: None) -> Self: ...
+	@overload
+	def get(self, instance: Any) -> T_co: ...
+	def get(self, *a, **kw): ...
+[builtins fixtures/dict.pyi]
+
 [case testSelfTypeSuper]
 from typing import TypeVar, cast
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-selftype.test::testSelfTypeOverrideCompatibilityTypeVar mypy/test/testcheck.py::TypeCheckSuite::check-selftype.test::testSelfTypeOverrideCompatibilitySelfTypeVar mypy/test/testcheck.py::TypeCheckSuite::check-selftype.test::testSelfTypeSuper
: '>>>>> End Test Output'
git checkout 5005428f6bf143d4f8d75b7cb9dd258d00e8ef14 -- test-data/unit/check-selftype.test 2>/dev/null || true
