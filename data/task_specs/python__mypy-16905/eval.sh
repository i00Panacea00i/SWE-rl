#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 837f7e0ed4f87869f314ec102c0d6e47ec3272ec -- test-data/unit/check-python310.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-python310.test b/test-data/unit/check-python310.test
--- a/test-data/unit/check-python310.test
+++ b/test-data/unit/check-python310.test
@@ -341,6 +341,72 @@ match m:
         reveal_type(m)  # N: Revealed type is "builtins.list[builtins.list[builtins.str]]"
 [builtins fixtures/list.pyi]
 
+[case testMatchSequencePatternNarrowSubjectItems]
+m: int
+n: str
+o: bool
+
+match m, n, o:
+    case [3, "foo", True]:
+        reveal_type(m)  # N: Revealed type is "Literal[3]"
+        reveal_type(n)  # N: Revealed type is "Literal['foo']"
+        reveal_type(o)  # N: Revealed type is "Literal[True]"
+    case [a, b, c]:
+        reveal_type(m)  # N: Revealed type is "builtins.int"
+        reveal_type(n)  # N: Revealed type is "builtins.str"
+        reveal_type(o)  # N: Revealed type is "builtins.bool"
+
+reveal_type(m)  # N: Revealed type is "builtins.int"
+reveal_type(n)  # N: Revealed type is "builtins.str"
+reveal_type(o)  # N: Revealed type is "builtins.bool"
+[builtins fixtures/tuple.pyi]
+
+[case testMatchSequencePatternNarrowSubjectItemsRecursive]
+m: int
+n: int
+o: int
+p: int
+q: int
+r: int
+
+match m, (n, o), (p, (q, r)):
+    case [0, [1, 2], [3, [4, 5]]]:
+        reveal_type(m)  # N: Revealed type is "Literal[0]"
+        reveal_type(n)  # N: Revealed type is "Literal[1]"
+        reveal_type(o)  # N: Revealed type is "Literal[2]"
+        reveal_type(p)  # N: Revealed type is "Literal[3]"
+        reveal_type(q)  # N: Revealed type is "Literal[4]"
+        reveal_type(r)  # N: Revealed type is "Literal[5]"
+[builtins fixtures/tuple.pyi]
+
+[case testMatchSequencePatternSequencesLengthMismatchNoNarrowing]
+m: int
+n: str
+o: bool
+
+match m, n, o:
+    case [3, "foo"]:
+        pass
+    case [3, "foo", True, True]:
+        pass
+[builtins fixtures/tuple.pyi]
+
+[case testMatchSequencePatternSequencesLengthMismatchNoNarrowingRecursive]
+m: int
+n: int
+o: int
+
+match m, (n, o):
+    case [0]:
+        pass
+    case [0, 1, [2]]:
+        pass
+    case [0, [1]]:
+        pass
+    case [0, [1, 2, 3]]:
+        pass
+[builtins fixtures/tuple.pyi]
+
 -- Mapping Pattern --
 
 [case testMatchMappingPatternCaptures]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchSequencePatternNarrowSubjectItemsRecursive mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchSequencePatternNarrowSubjectItems mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchMappingPatternCapturesTypedDictWithLiteral mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchMappingPatternCapturesTypedDictUnreachable mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchMappingPatternCaptures mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchMappingPatternCapturesWrongKeyType mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchMappingPatternCapturesTypedDict mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchMappingPatternCapturesTypedDictWithNonLiteral mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchSequencePatternSequencesLengthMismatchNoNarrowing mypy/test/testcheck.py::TypeCheckSuite::check-python310.test::testMatchSequencePatternSequencesLengthMismatchNoNarrowingRecursive
: '>>>>> End Test Output'
git checkout 837f7e0ed4f87869f314ec102c0d6e47ec3272ec -- test-data/unit/check-python310.test 2>/dev/null || true
