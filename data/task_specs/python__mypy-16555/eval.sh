#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 5b1a231425ac807b7118aac6a68b633949412a36 -- test-data/unit/check-formatting.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-formatting.test b/test-data/unit/check-formatting.test
--- a/test-data/unit/check-formatting.test
+++ b/test-data/unit/check-formatting.test
@@ -588,3 +588,45 @@ class S:
 '{:%}'.format(0.001)
 [builtins fixtures/primitives.pyi]
 [typing fixtures/typing-medium.pyi]
+
+[case testEnumWithStringToFormatValue]
+from enum import Enum
+
+class Responses(str, Enum):
+    TEMPLATED = 'insert {} here'
+    TEMPLATED_WITH_KW = 'insert {value} here'
+    NORMAL = 'something'
+
+Responses.TEMPLATED.format(42)
+Responses.TEMPLATED_WITH_KW.format(value=42)
+Responses.TEMPLATED.format()  # E: Cannot find replacement for positional format specifier 0
+Responses.TEMPLATED_WITH_KW.format()  # E: Cannot find replacement for named format specifier "value"
+Responses.NORMAL.format(42)  # E: Not all arguments converted during string formatting
+Responses.NORMAL.format(value=42)  # E: Not all arguments converted during string formatting
+[builtins fixtures/primitives.pyi]
+
+[case testNonStringEnumToFormatValue]
+from enum import Enum
+
+class Responses(Enum):
+    TEMPLATED = 'insert {value} here'
+
+Responses.TEMPLATED.format(value=42)  # E: "Responses" has no attribute "format"
+[builtins fixtures/primitives.pyi]
+
+[case testStrEnumWithStringToFormatValue]
+# flags: --python-version 3.11
+from enum import StrEnum
+
+class Responses(StrEnum):
+    TEMPLATED = 'insert {} here'
+    TEMPLATED_WITH_KW = 'insert {value} here'
+    NORMAL = 'something'
+
+Responses.TEMPLATED.format(42)
+Responses.TEMPLATED_WITH_KW.format(value=42)
+Responses.TEMPLATED.format()  # E: Cannot find replacement for positional format specifier 0
+Responses.TEMPLATED_WITH_KW.format()  # E: Cannot find replacement for named format specifier "value"
+Responses.NORMAL.format(42)  # E: Not all arguments converted during string formatting
+Responses.NORMAL.format(value=42)  # E: Not all arguments converted during string formatting
+[builtins fixtures/primitives.pyi]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::check-formatting.test::testNonStringEnumToFormatValue mypy/test/testcheck.py::TypeCheckSuite::check-formatting.test::testStrEnumWithStringToFormatValue mypy/test/testcheck.py::TypeCheckSuite::check-formatting.test::testEnumWithStringToFormatValue
: '>>>>> End Test Output'
git checkout 5b1a231425ac807b7118aac6a68b633949412a36 -- test-data/unit/check-formatting.test 2>/dev/null || true
