#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout fce520d45a304ee2659bb4156acf484cee5aea07 -- pandas/tests/io/json/test_normalize.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/io/json/test_normalize.py b/pandas/tests/io/json/test_normalize.py
index 7914d40ea8aaa..0f33883feba3a 100644
--- a/pandas/tests/io/json/test_normalize.py
+++ b/pandas/tests/io/json/test_normalize.py
@@ -526,8 +526,8 @@ def test_non_list_record_path_errors(self, value):
         test_input = {"state": "Texas", "info": parsed_value}
         test_path = "info"
         msg = (
-            f"{test_input} has non list value {parsed_value} for path {test_path}. "
-            "Must be list or null."
+            f"Path must contain list or null, "
+            f"but got {type(parsed_value).__name__} at 'info'"
         )
         with pytest.raises(TypeError, match=msg):
             json_normalize([test_input], record_path=[test_path])

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_non_list_record_path_errors[{}]' 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_non_list_record_path_errors["text"]' 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_non_list_record_path_errors[true]' 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_non_list_record_path_errors[1]' 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_non_list_record_path_errors[false]' pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_json_normalize_errors pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_missing_meta_multilevel_record_path_errors_raise pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_missing_meta 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_accepted_input[{"a":' pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_one_level_deep_flattens 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_accepted_input[data0-None-None]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_value_array_record_prefix pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_simple_normalize 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nonetype_record_path[Decimal]' 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_accepted_input[None-None-NotImplementedError]' 'pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_with_max_level[0-expected1]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nested_object_record_path pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_missing_field 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_max_level_with_records_path[1-expected1]' pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_nested_flattens 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_accepted_input[data1-a-None]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_simple_normalize_with_separator pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_donot_drop_nonevalues 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nonetype_record_path[NaTType]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_shallow_nested pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_missing_meta_multilevel_record_path_errors_ignore 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nonetype_record_path[float1]' pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_nonetype_multiple_levels 'pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_with_max_level[None-expected0]' pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_series_non_zero_index pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_nonetype_top_level_bottom_level pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_flat_stays_flat 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nonetype_record_path[float0]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_simple_records pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_meta_non_iterable pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_generator pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_more_deeply_nested pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_empty_array pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_with_large_max_level pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_meta_parameter_not_modified pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_normalize_with_multichar_separator pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_fields_list_type_normalize pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_non_ascii_key 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nonetype_record_path[NoneType]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_record_prefix pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nested_meta_path_with_nested_record_path 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_max_level_with_records_path[0-expected0]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nested_flattening_consistent 'pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_nonetype_record_path[NAType]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_meta_name_conflict pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_missing_nested_meta 'pandas/tests/io/json/test_normalize.py::TestNestedToRecord::test_with_max_level[1-expected2]' pandas/tests/io/json/test_normalize.py::TestJSONNormalize::test_top_column_with_leading_underscore
: '>>>>> End Test Output'
git checkout fce520d45a304ee2659bb4156acf484cee5aea07 -- pandas/tests/io/json/test_normalize.py 2>/dev/null || true
