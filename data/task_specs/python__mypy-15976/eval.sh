#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout d7b24514d7301f86031b7d1e2215cf8c2476bec0 -- test-data/unit/check-dataclasses.test test-data/unit/check-plugin-attrs.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-dataclasses.test b/test-data/unit/check-dataclasses.test
--- a/test-data/unit/check-dataclasses.test
+++ b/test-data/unit/check-dataclasses.test
@@ -1519,6 +1519,22 @@ class Some:
         self.y = 1  # E: Trying to assign name "y" that is not in "__slots__" of type "__main__.Some"
 [builtins fixtures/dataclasses.pyi]
 
+[case testDataclassWithSlotsDerivedFromNonSlot]
+# flags: --python-version 3.10
+from dataclasses import dataclass
+
+class A:
+    pass
+
+@dataclass(slots=True)
+class B(A):
+    x: int
+
+    def __post_init__(self) -> None:
+        self.y = 42
+
+[builtins fixtures/dataclasses.pyi]
+
 [case testDataclassWithSlotsConflict]
 # flags: --python-version 3.10
 from dataclasses import dataclass
diff --git a/test-data/unit/check-plugin-attrs.test b/test-data/unit/check-plugin-attrs.test
--- a/test-data/unit/check-plugin-attrs.test
+++ b/test-data/unit/check-plugin-attrs.test
@@ -1677,6 +1677,21 @@ class C:
         self.c = 2  # E: Trying to assign name "c" that is not in "__slots__" of type "__main__.C"
 [builtins fixtures/plugin_attrs.pyi]
 
+[case testAttrsClassWithSlotsDerivedFromNonSlots]
+import attrs
+
+class A:
+    pass
+
+@attrs.define(slots=True)
+class B(A):
+    x: int
+
+    def __attrs_post_init__(self) -> None:
+        self.y = 42
+
+[builtins fixtures/plugin_attrs.pyi]
+
 [case testRuntimeSlotsAttr]
 from attr import dataclass
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-dataclasses.test::testDataclassWithSlotsDerivedFromNonSlot mypy/test/testcheck.py::TypeCheckSuite::check-plugin-attrs.test::testAttrsClassWithSlotsDerivedFromNonSlots mypy/test/testcheck.py::TypeCheckSuite::check-plugin-attrs.test::testRuntimeSlotsAttr mypy/test/testcheck.py::TypeCheckSuite::check-dataclasses.test::testDataclassWithSlotsConflict
: '>>>>> End Test Output'
git checkout d7b24514d7301f86031b7d1e2215cf8c2476bec0 -- test-data/unit/check-dataclasses.test test-data/unit/check-plugin-attrs.test 2>/dev/null || true
