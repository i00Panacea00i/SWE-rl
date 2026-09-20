#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout f96446ce2f99a86210b21d39c7aec4b13a8bfc66 -- test-data/unit/check-dataclasses.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-dataclasses.test b/test-data/unit/check-dataclasses.test
--- a/test-data/unit/check-dataclasses.test
+++ b/test-data/unit/check-dataclasses.test
@@ -1456,3 +1456,69 @@ class Other:
     __slots__ = ('x',)
     x: int
 [builtins fixtures/dataclasses.pyi]
+
+
+[case testSlotsDefinitionWithTwoPasses1]
+# flags: --python-version 3.10
+# https://github.com/python/mypy/issues/11821
+from typing import TypeVar, Protocol, Generic
+from dataclasses import dataclass
+
+C = TypeVar("C", bound="Comparable")
+
+class Comparable(Protocol):
+    pass
+
+V = TypeVar("V", bound=Comparable)
+
+@dataclass(slots=True)
+class Node(Generic[V]):  # Error was here
+    data: V
+[builtins fixtures/dataclasses.pyi]
+
+[case testSlotsDefinitionWithTwoPasses2]
+# flags: --python-version 3.10
+from typing import TypeVar, Protocol, Generic
+from dataclasses import dataclass
+
+C = TypeVar("C", bound="Comparable")
+
+class Comparable(Protocol):
+    pass
+
+V = TypeVar("V", bound=Comparable)
+
+@dataclass(slots=True)  # Explicit slots are still not ok:
+class Node(Generic[V]):  # E: "Node" both defines "__slots__" and is used with "slots=True"
+    __slots__ = ('data',)
+    data: V
+[builtins fixtures/dataclasses.pyi]
+
+[case testSlotsDefinitionWithTwoPasses3]
+# flags: --python-version 3.10
+from typing import TypeVar, Protocol, Generic
+from dataclasses import dataclass
+
+C = TypeVar("C", bound="Comparable")
+
+class Comparable(Protocol):
+    pass
+
+V = TypeVar("V", bound=Comparable)
+
+@dataclass(slots=True)  # Explicit slots are still not ok, even empty ones:
+class Node(Generic[V]):  # E: "Node" both defines "__slots__" and is used with "slots=True"
+    __slots__ = ()
+    data: V
+[builtins fixtures/dataclasses.pyi]
+
+[case testSlotsDefinitionWithTwoPasses4]
+# flags: --python-version 3.10
+import dataclasses as dtc
+
+PublishedMessagesVar = dict[int, 'PublishedMessages']
+
+@dtc.dataclass(frozen=True, slots=True)
+class PublishedMessages:
+    left: int
+[builtins fixtures/dataclasses.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-dataclasses.test::testSlotsDefinitionWithTwoPasses4 mypy/test/testcheck.py::TypeCheckSuite::check-dataclasses.test::testSlotsDefinitionWithTwoPasses1 mypy/test/testcheck.py::TypeCheckSuite::check-dataclasses.test::testSlotsDefinitionWithTwoPasses2 mypy/test/testcheck.py::TypeCheckSuite::check-dataclasses.test::testSlotsDefinitionWithTwoPasses3
: '>>>>> End Test Output'
git checkout f96446ce2f99a86210b21d39c7aec4b13a8bfc66 -- test-data/unit/check-dataclasses.test 2>/dev/null || true
