#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 781dc8f82adacce730293479517fd0fb5944c255 -- test-data/unit/check-selftype.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-selftype.test b/test-data/unit/check-selftype.test
--- a/test-data/unit/check-selftype.test
+++ b/test-data/unit/check-selftype.test
@@ -1665,6 +1665,23 @@ class C:
         return cls()
 [builtins fixtures/classmethod.pyi]
 
+[case testTypingSelfRedundantAllowed_pep585]
+# flags: --python-version 3.9
+from typing import Self
+
+class C:
+    def f(self: Self) -> Self:
+        d: Defer
+        class Defer: ...
+        return self
+
+    @classmethod
+    def g(cls: type[Self]) -> Self:
+        d: DeferAgain
+        class DeferAgain: ...
+        return cls()
+[builtins fixtures/classmethod.pyi]
+
 [case testTypingSelfRedundantWarning]
 # mypy: enable-error-code="redundant-self"
 
@@ -1683,6 +1700,25 @@ class C:
         return cls()
 [builtins fixtures/classmethod.pyi]
 
+[case testTypingSelfRedundantWarning_pep585]
+# flags: --python-version 3.9
+# mypy: enable-error-code="redundant-self"
+
+from typing import Self
+
+class C:
+    def copy(self: Self) -> Self:  # E: Redundant "Self" annotation for the first method argument
+        d: Defer
+        class Defer: ...
+        return self
+
+    @classmethod
+    def g(cls: type[Self]) -> Self:  # E: Redundant "Self" annotation for the first method argument
+        d: DeferAgain
+        class DeferAgain: ...
+        return cls()
+[builtins fixtures/classmethod.pyi]
+
 [case testTypingSelfAssertType]
 from typing import Self, assert_type
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-selftype.test::testTypingSelfRedundantWarning_pep585 mypy/test/testcheck.py::TypeCheckSuite::check-selftype.test::testTypingSelfRedundantAllowed_pep585 mypy/test/testcheck.py::TypeCheckSuite::check-selftype.test::testTypingSelfRedundantWarning mypy/test/testcheck.py::TypeCheckSuite::check-selftype.test::testTypingSelfAssertType
: '>>>>> End Test Output'
git checkout 781dc8f82adacce730293479517fd0fb5944c255 -- test-data/unit/check-selftype.test 2>/dev/null || true
