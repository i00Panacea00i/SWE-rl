#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout f2978c3b1b23ea939db58332f94876b73bc01d65 -- test-data/unit/check-enum.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-enum.test b/test-data/unit/check-enum.test
--- a/test-data/unit/check-enum.test
+++ b/test-data/unit/check-enum.test
@@ -1391,3 +1391,256 @@ class Foo(Enum):
         x = 3
 x = 4
 [builtins fixtures/bool.pyi]
+
+[case testEnumImplicitlyFinalForSubclassing]
+from enum import Enum, IntEnum, Flag, IntFlag
+
+class NonEmptyEnum(Enum):
+    x = 1
+class NonEmptyIntEnum(IntEnum):
+    x = 1
+class NonEmptyFlag(Flag):
+    x = 1
+class NonEmptyIntFlag(IntFlag):
+    x = 1
+
+class ErrorEnumWithValue(NonEmptyEnum):  # E: Cannot inherit from final class "NonEmptyEnum"
+    x = 1
+class ErrorIntEnumWithValue(NonEmptyIntEnum):  # E: Cannot inherit from final class "NonEmptyIntEnum"
+    x = 1
+class ErrorFlagWithValue(NonEmptyFlag):  # E: Cannot inherit from final class "NonEmptyFlag"
+    x = 1
+class ErrorIntFlagWithValue(NonEmptyIntFlag):  # E: Cannot inherit from final class "NonEmptyIntFlag"
+    x = 1
+
+class ErrorEnumWithoutValue(NonEmptyEnum):  # E: Cannot inherit from final class "NonEmptyEnum"
+    pass
+class ErrorIntEnumWithoutValue(NonEmptyIntEnum):  # E: Cannot inherit from final class "NonEmptyIntEnum"
+    pass
+class ErrorFlagWithoutValue(NonEmptyFlag):  # E: Cannot inherit from final class "NonEmptyFlag"
+    pass
+class ErrorIntFlagWithoutValue(NonEmptyIntFlag):  # E: Cannot inherit from final class "NonEmptyIntFlag"
+    pass
+[builtins fixtures/bool.pyi]
+
+[case testSubclassingNonFinalEnums]
+from enum import Enum, IntEnum, Flag, IntFlag, EnumMeta
+
+def decorator(func):
+    return func
+
+class EmptyEnum(Enum):
+    pass
+class EmptyIntEnum(IntEnum):
+    pass
+class EmptyFlag(Flag):
+    pass
+class EmptyIntFlag(IntFlag):
+    pass
+class EmptyEnumMeta(EnumMeta):
+    pass
+
+class NonEmptyEnumSub(EmptyEnum):
+    x = 1
+class NonEmptyIntEnumSub(EmptyIntEnum):
+    x = 1
+class NonEmptyFlagSub(EmptyFlag):
+    x = 1
+class NonEmptyIntFlagSub(EmptyIntFlag):
+    x = 1
+class NonEmptyEnumMetaSub(EmptyEnumMeta):
+    x = 1
+
+class EmptyEnumSub(EmptyEnum):
+    def method(self) -> None: pass
+    @decorator
+    def other(self) -> None: pass
+class EmptyIntEnumSub(EmptyIntEnum):
+    def method(self) -> None: pass
+class EmptyFlagSub(EmptyFlag):
+    def method(self) -> None: pass
+class EmptyIntFlagSub(EmptyIntFlag):
+    def method(self) -> None: pass
+class EmptyEnumMetaSub(EmptyEnumMeta):
+    def method(self) -> None: pass
+
+class NestedEmptyEnumSub(EmptyEnumSub):
+    x = 1
+class NestedEmptyIntEnumSub(EmptyIntEnumSub):
+    x = 1
+class NestedEmptyFlagSub(EmptyFlagSub):
+    x = 1
+class NestedEmptyIntFlagSub(EmptyIntFlagSub):
+    x = 1
+class NestedEmptyEnumMetaSub(EmptyEnumMetaSub):
+    x = 1
+[builtins fixtures/bool.pyi]
+
+[case testEnumExplicitlyAndImplicitlyFinal]
+from typing import final
+from enum import Enum, IntEnum, Flag, IntFlag, EnumMeta
+
+@final
+class EmptyEnum(Enum):
+    pass
+@final
+class EmptyIntEnum(IntEnum):
+    pass
+@final
+class EmptyFlag(Flag):
+    pass
+@final
+class EmptyIntFlag(IntFlag):
+    pass
+@final
+class EmptyEnumMeta(EnumMeta):
+    pass
+
+class EmptyEnumSub(EmptyEnum):  # E: Cannot inherit from final class "EmptyEnum"
+    pass
+class EmptyIntEnumSub(EmptyIntEnum):  # E: Cannot inherit from final class "EmptyIntEnum"
+    pass
+class EmptyFlagSub(EmptyFlag):  # E: Cannot inherit from final class "EmptyFlag"
+    pass
+class EmptyIntFlagSub(EmptyIntFlag):  # E: Cannot inherit from final class "EmptyIntFlag"
+    pass
+class EmptyEnumMetaSub(EmptyEnumMeta):  # E: Cannot inherit from final class "EmptyEnumMeta"
+    pass
+
+@final
+class NonEmptyEnum(Enum):
+    x = 1
+@final
+class NonEmptyIntEnum(IntEnum):
+    x = 1
+@final
+class NonEmptyFlag(Flag):
+    x = 1
+@final
+class NonEmptyIntFlag(IntFlag):
+    x = 1
+@final
+class NonEmptyEnumMeta(EnumMeta):
+    x = 1
+
+class ErrorEnumWithoutValue(NonEmptyEnum):  # E: Cannot inherit from final class "NonEmptyEnum"
+    pass
+class ErrorIntEnumWithoutValue(NonEmptyIntEnum):  # E: Cannot inherit from final class "NonEmptyIntEnum"
+    pass
+class ErrorFlagWithoutValue(NonEmptyFlag):  # E: Cannot inherit from final class "NonEmptyFlag"
+    pass
+class ErrorIntFlagWithoutValue(NonEmptyIntFlag):  # E: Cannot inherit from final class "NonEmptyIntFlag"
+    pass
+class ErrorEnumMetaWithoutValue(NonEmptyEnumMeta):  # E: Cannot inherit from final class "NonEmptyEnumMeta"
+    pass
+[builtins fixtures/bool.pyi]
+
+[case testEnumFinalSubtypingEnumMetaSpecialCase]
+from enum import EnumMeta
+# `EnumMeta` types are not `Enum`s
+class SubMeta(EnumMeta):
+    x = 1
+class SubSubMeta(SubMeta):
+    x = 2
+[builtins fixtures/bool.pyi]
+
+[case testEnumFinalSubtypingOverloadedSpecialCase]
+from typing import overload
+from enum import Enum, IntEnum, Flag, IntFlag, EnumMeta
+
+class EmptyEnum(Enum):
+    @overload
+    def method(self, arg: int) -> int:
+        pass
+    @overload
+    def method(self, arg: str) -> str:
+        pass
+    def method(self, arg):
+        pass
+class EmptyIntEnum(IntEnum):
+    @overload
+    def method(self, arg: int) -> int:
+        pass
+    @overload
+    def method(self, arg: str) -> str:
+        pass
+    def method(self, arg):
+        pass
+class EmptyFlag(Flag):
+    @overload
+    def method(self, arg: int) -> int:
+        pass
+    @overload
+    def method(self, arg: str) -> str:
+        pass
+    def method(self, arg):
+        pass
+class EmptyIntFlag(IntFlag):
+    @overload
+    def method(self, arg: int) -> int:
+        pass
+    @overload
+    def method(self, arg: str) -> str:
+        pass
+    def method(self, arg):
+        pass
+class EmptyEnumMeta(EnumMeta):
+    @overload
+    def method(self, arg: int) -> int:
+        pass
+    @overload
+    def method(self, arg: str) -> str:
+        pass
+    def method(self, arg):
+        pass
+
+class NonEmptyEnumSub(EmptyEnum):
+    x = 1
+class NonEmptyIntEnumSub(EmptyIntEnum):
+    x = 1
+class NonEmptyFlagSub(EmptyFlag):
+    x = 1
+class NonEmptyIntFlagSub(EmptyIntFlag):
+    x = 1
+class NonEmptyEnumMetaSub(EmptyEnumMeta):
+    x = 1
+[builtins fixtures/bool.pyi]
+
+[case testEnumFinalSubtypingMethodAndValueSpecialCase]
+from enum import Enum, IntEnum, Flag, IntFlag, EnumMeta
+
+def decorator(func):
+    return func
+
+class NonEmptyEnum(Enum):
+    x = 1
+    def method(self) -> None: pass
+    @decorator
+    def other(self) -> None: pass
+class NonEmptyIntEnum(IntEnum):
+    x = 1
+    def method(self) -> None: pass
+class NonEmptyFlag(Flag):
+    x = 1
+    def method(self) -> None: pass
+class NonEmptyIntFlag(IntFlag):
+    x = 1
+    def method(self) -> None: pass
+
+class ErrorEnumWithoutValue(NonEmptyEnum):  # E: Cannot inherit from final class "NonEmptyEnum"
+    pass
+class ErrorIntEnumWithoutValue(NonEmptyIntEnum):  # E: Cannot inherit from final class "NonEmptyIntEnum"
+    pass
+class ErrorFlagWithoutValue(NonEmptyFlag):  # E: Cannot inherit from final class "NonEmptyFlag"
+    pass
+class ErrorIntFlagWithoutValue(NonEmptyIntFlag):  # E: Cannot inherit from final class "NonEmptyIntFlag"
+    pass
+[builtins fixtures/bool.pyi]
+
+[case testFinalEnumWithClassDef]
+from enum import Enum
+
+class A(Enum):
+    class Inner: pass
+class B(A): pass  # E: Cannot inherit from final class "A"
+[builtins fixtures/bool.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testFinalEnumWithClassDef mypy/test/testcheck.py::TypeCheckSuite::testEnumImplicitlyFinalForSubclassing mypy/test/testcheck.py::TypeCheckSuite::testEnumFinalSubtypingMethodAndValueSpecialCase mypy/test/testcheck.py::TypeCheckSuite::testEnumFinalSubtypingEnumMetaSpecialCase mypy/test/testcheck.py::TypeCheckSuite::testSubclassingNonFinalEnums mypy/test/testcheck.py::TypeCheckSuite::testEnumExplicitlyAndImplicitlyFinal mypy/test/testcheck.py::TypeCheckSuite::testEnumFinalSubtypingOverloadedSpecialCase
: '>>>>> End Test Output'
git checkout f2978c3b1b23ea939db58332f94876b73bc01d65 -- test-data/unit/check-enum.test 2>/dev/null || true
