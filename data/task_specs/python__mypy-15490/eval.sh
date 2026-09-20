#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 304997bfb85200fb521ac727ee0ce3e6085e5278 -- test-data/unit/check-protocols.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-protocols.test b/test-data/unit/check-protocols.test
--- a/test-data/unit/check-protocols.test
+++ b/test-data/unit/check-protocols.test
@@ -2789,6 +2789,70 @@ class A(Protocol):
 
 [builtins fixtures/tuple.pyi]
 
+[case testProtocolSlotsIsNotProtocolMember]
+# https://github.com/python/mypy/issues/11884
+from typing import Protocol
+
+class Foo(Protocol):
+    __slots__ = ()
+class NoSlots:
+    pass
+class EmptySlots:
+    __slots__ = ()
+class TupleSlots:
+    __slots__ = ('x', 'y')
+class StringSlots:
+    __slots__ = 'x y'
+class InitSlots:
+    __slots__ = ('x',)
+    def __init__(self) -> None:
+        self.x = None
+def foo(f: Foo):
+    pass
+
+# All should pass:
+foo(NoSlots())
+foo(EmptySlots())
+foo(TupleSlots())
+foo(StringSlots())
+foo(InitSlots())
+[builtins fixtures/tuple.pyi]
+
+[case testProtocolSlotsAndRuntimeCheckable]
+from typing import Protocol, runtime_checkable
+
+@runtime_checkable
+class Foo(Protocol):
+    __slots__ = ()
+class Bar:
+    pass
+issubclass(Bar, Foo)  # Used to be an error, when `__slots__` counted as a protocol member
+[builtins fixtures/isinstance.pyi]
+[typing fixtures/typing-full.pyi]
+
+
+[case testProtocolWithClassGetItem]
+# https://github.com/python/mypy/issues/11886
+from typing import Any, Iterable, Protocol, Union
+
+class B:
+    ...
+
+class C:
+    def __class_getitem__(cls, __item: Any) -> Any:
+        ...
+
+class SupportsClassGetItem(Protocol):
+    __slots__: Union[str, Iterable[str]] = ()
+    def __class_getitem__(cls, __item: Any) -> Any:
+        ...
+
+b1: SupportsClassGetItem = B()
+c1: SupportsClassGetItem = C()
+[builtins fixtures/tuple.pyi]
+[typing fixtures/typing-full.pyi]
+
+
 [case testNoneVsProtocol]
 # mypy: strict-optional
 from typing_extensions import Protocol

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-protocols.test::testProtocolWithClassGetItem mypy/test/testcheck.py::TypeCheckSuite::check-protocols.test::testProtocolSlotsAndRuntimeCheckable mypy/test/testcheck.py::TypeCheckSuite::check-protocols.test::testProtocolSlotsIsNotProtocolMember mypy/test/testcheck.py::TypeCheckSuite::check-protocols.test::testNoneVsProtocol
: '>>>>> End Test Output'
git checkout 304997bfb85200fb521ac727ee0ce3e6085e5278 -- test-data/unit/check-protocols.test 2>/dev/null || true
