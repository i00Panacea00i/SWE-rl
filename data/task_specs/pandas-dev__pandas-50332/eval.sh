#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 3da778cb04a2f62461f103c1669ff02f430f9171 -- pandas/tests/io/json/test_json_table_schema_ext_dtype.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/io/json/test_json_table_schema_ext_dtype.py b/pandas/tests/io/json/test_json_table_schema_ext_dtype.py
index ae926173e129b..cf521aafdc241 100644
--- a/pandas/tests/io/json/test_json_table_schema_ext_dtype.py
+++ b/pandas/tests/io/json/test_json_table_schema_ext_dtype.py
@@ -8,9 +8,13 @@
 import pytest
 
 from pandas import (
+    NA,
     DataFrame,
+    Index,
     array,
+    read_json,
 )
+import pandas._testing as tm
 from pandas.core.arrays.integer import Int64Dtype
 from pandas.core.arrays.string_ import StringDtype
 from pandas.core.series import Series
@@ -273,3 +277,43 @@ def test_to_json(self, df):
         expected = OrderedDict([("schema", schema), ("data", data)])
 
         assert result == expected
+
+    def test_json_ext_dtype_reading_roundtrip(self):
+        # GH#40255
+        df = DataFrame(
+            {
+                "a": Series([2, NA], dtype="Int64"),
+                "b": Series([1.5, NA], dtype="Float64"),
+                "c": Series([True, NA], dtype="boolean"),
+            },
+            index=Index([1, NA], dtype="Int64"),
+        )
+        expected = df.copy()
+        data_json = df.to_json(orient="table", indent=4)
+        result = read_json(data_json, orient="table")
+        tm.assert_frame_equal(result, expected)
+
+    def test_json_ext_dtype_reading(self):
+        # GH#40255
+        data_json = """{
+            "schema":{
+                "fields":[
+                    {
+                        "name":"a",
+                        "type":"integer",
+                        "extDtype":"Int64"
+                    }
+                ],
+            },
+            "data":[
+                {
+                    "a":2
+                },
+                {
+                    "a":null
+                }
+            ]
+        }"""
+        result = read_json(data_json, orient="table")
+        expected = DataFrame({"a": Series([2, NA], dtype="Int64")})
+        tm.assert_frame_equal(result, expected)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableOrient::test_json_ext_dtype_reading pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableOrient::test_json_ext_dtype_reading_roundtrip 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_date_array_dtype[date_data0]' pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_date_dtype 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_decimal_array_dtype[decimal_data0]' 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_date_array_dtype[date_data1]' 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_string_array_dtype[string_data1]' 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_date_array_dtype[date_data2]' pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_string_dtype pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableOrient::test_build_int64_series pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestBuildSchema::test_build_table_schema 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_string_array_dtype[string_data0]' pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableOrient::test_build_string_series 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_decimal_array_dtype[decimal_data1]' pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_decimal_dtype pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableOrient::test_build_date_series pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_integer_dtype pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableOrient::test_build_decimal_series 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_integer_array_dtype[integer_data1]' pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableOrient::test_to_json 'pandas/tests/io/json/test_json_table_schema_ext_dtype.py::TestTableSchemaType::test_as_json_table_type_ext_integer_array_dtype[integer_data0]'
: '>>>>> End Test Output'
git checkout 3da778cb04a2f62461f103c1669ff02f430f9171 -- pandas/tests/io/json/test_json_table_schema_ext_dtype.py 2>/dev/null || true
