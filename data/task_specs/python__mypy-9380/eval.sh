#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout a79f1aaade9fe150a4bc9bb1d5ad287824298f74 -- test-data/unit/check-dataclasses.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-dataclasses.test b/test-data/unit/check-dataclasses.test
--- a/test-data/unit/check-dataclasses.test
+++ b/test-data/unit/check-dataclasses.test
@@ -480,6 +480,102 @@ s: str = a.bar()  # E: Incompatible types in assignment (expression has type "in
 
 [builtins fixtures/list.pyi]
 
+
+[case testDataclassUntypedGenericInheritance]
+from dataclasses import dataclass
+from typing import Generic, TypeVar
+
+T = TypeVar("T")
+
+@dataclass
+class Base(Generic[T]):
+    attr: T
+
+@dataclass
+class Sub(Base):
+    pass
+
+sub = Sub(attr=1)
+reveal_type(sub)  # N: Revealed type is '__main__.Sub'
+reveal_type(sub.attr)  # N: Revealed type is 'Any'
+
+
+[case testDataclassGenericSubtype]
+from dataclasses import dataclass
+from typing import Generic, TypeVar
+
+T = TypeVar("T")
+
+@dataclass
+class Base(Generic[T]):
+    attr: T
+
+S = TypeVar("S")
+
+@dataclass
+class Sub(Base[S]):
+    pass
+
+sub_int = Sub[int](attr=1)
+reveal_type(sub_int)  # N: Revealed type is '__main__.Sub[builtins.int*]'
+reveal_type(sub_int.attr)  # N: Revealed type is 'builtins.int*'
+
+sub_str = Sub[str](attr='ok')
+reveal_type(sub_str)  # N: Revealed type is '__main__.Sub[builtins.str*]'
+reveal_type(sub_str.attr)  # N: Revealed type is 'builtins.str*'
+
+
+[case testDataclassGenericInheritance]
+from dataclasses import dataclass
+from typing import Generic, TypeVar
+
+T1 = TypeVar("T1")
+T2 = TypeVar("T2")
+T3 = TypeVar("T3")
+
+@dataclass
+class Base(Generic[T1, T2, T3]):
+    one: T1
+    two: T2
+    three: T3
+
+@dataclass
+class Sub(Base[int, str, float]):
+    pass
+
+sub = Sub(one=1, two='ok', three=3.14)
+reveal_type(sub)  # N: Revealed type is '__main__.Sub'
+reveal_type(sub.one)  # N: Revealed type is 'builtins.int*'
+reveal_type(sub.two)  # N: Revealed type is 'builtins.str*'
+reveal_type(sub.three)  # N: Revealed type is 'builtins.float*'
+
+
+[case testDataclassMultiGenericInheritance]
+from dataclasses import dataclass
+from typing import Generic, TypeVar
+
+T = TypeVar("T")
+
+@dataclass
+class Base(Generic[T]):
+    base_attr: T
+
+S = TypeVar("S")
+
+@dataclass
+class Middle(Base[int], Generic[S]):
+    middle_attr: S
+
+@dataclass
+class Sub(Middle[str]):
+    pass
+
+sub = Sub(base_attr=1, middle_attr='ok')
+reveal_type(sub)  # N: Revealed type is '__main__.Sub'
+reveal_type(sub.base_attr)  # N: Revealed type is 'builtins.int*'
+reveal_type(sub.middle_attr)  # N: Revealed type is 'builtins.str*'
+
+
 [case testDataclassGenericsClassmethod]
 # flags: --python-version 3.6
 from dataclasses import dataclass

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testDataclassUntypedGenericInheritance mypy/test/testcheck.py::TypeCheckSuite::testDataclassMultiGenericInheritance mypy/test/testcheck.py::TypeCheckSuite::testDataclassGenericInheritance mypy/test/testcheck.py::TypeCheckSuite::testDataclassGenericSubtype mypy/test/testcheck.py::TypeCheckSuite::testDataclassGenericsClassmethod
: '>>>>> End Test Output'
git checkout a79f1aaade9fe150a4bc9bb1d5ad287824298f74 -- test-data/unit/check-dataclasses.test 2>/dev/null || true
