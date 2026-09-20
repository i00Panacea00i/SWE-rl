#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout fc37c83c2deb59253ae2d10ca631b6a1242cfdcb -- pandas/tests/tslibs/test_array_to_datetime.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/tslibs/test_array_to_datetime.py b/pandas/tests/tslibs/test_array_to_datetime.py
index 30ea3a70552aa..89328e4bb0032 100644
--- a/pandas/tests/tslibs/test_array_to_datetime.py
+++ b/pandas/tests/tslibs/test_array_to_datetime.py
@@ -262,6 +262,23 @@ def test_to_datetime_barely_out_of_bounds():
         tslib.array_to_datetime(arr)
 
 
+@pytest.mark.parametrize(
+    "timestamp",
+    [
+        # Close enough to bounds that scaling micros to nanos overflows
+        # but adding nanos would result in an in-bounds datetime.
+        "1677-09-21T00:12:43.145224193",
+        "1677-09-21T00:12:43.145224999",
+        # this always worked
+        "1677-09-21T00:12:43.145225000",
+    ],
+)
+def test_to_datetime_barely_inside_bounds(timestamp):
+    # see gh-57150
+    result, _ = tslib.array_to_datetime(np.array([timestamp], dtype=object))
+    tm.assert_numpy_array_equal(result, np.array([timestamp], dtype="M8[ns]"))
+
+
 class SubDatetime(datetime):
     pass
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail 'pandas/tests/tslibs/test_array_to_datetime.py::test_to_datetime_barely_inside_bounds[1677-09-21T00:12:43.145224193]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_to_datetime_barely_inside_bounds[1677-09-21T00:12:43.145224999]' pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_homogeoneous_datetimes_strings 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[coerce-invalid_date0]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_parsing_timezone_offsets[2013-01-01T08:00:00.000000000+0800-480]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[raise-1000-01-01]' pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_homogeoneous_dt64 'pandas/tests/tslibs/test_array_to_datetime.py::test_parsing_valid_dates[data1-expected1]' pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeWithTZResolutionInference::test_array_to_datetime_with_tz_resolution_all_nat pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_all_nat 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[coerce-invalid_date4]' pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeWithTZResolutionInference::test_array_to_datetime_with_tz_resolution pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_of_invalid_datetimes 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[coerce-invalid_date1]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[raise-invalid_date4]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_parsing_valid_dates[data0-expected0]' 'pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_with_nat_int_float_str[]' 'pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_with_nat_int_float_str[-9223372036854775808]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_datetime_subclass[Timestamp]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[raise-invalid_date0]' pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds_one_valid 'pandas/tests/tslibs/test_array_to_datetime.py::test_parsing_timezone_offsets[2012-12-31T16:00:00.000000000-0800--480]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[raise-invalid_date1]' pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_homogeoneous_timestamps 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[coerce-1000-01-01]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_to_datetime_barely_inside_bounds[1677-09-21T00:12:43.145225000]' pandas/tests/tslibs/test_array_to_datetime.py::test_parsing_non_iso_timezone_offset 'pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_with_nat_int_float_str[-9.223372036854776e+18]' pandas/tests/tslibs/test_array_to_datetime.py::test_to_datetime_barely_out_of_bounds 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[coerce-Jan' 'pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_with_nat_int_float_str[NaT]' pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_heterogeneous pandas/tests/tslibs/test_array_to_datetime.py::test_parsing_different_timezone_offsets 'pandas/tests/tslibs/test_array_to_datetime.py::test_coerce_outside_ns_bounds[raise-Jan' 'pandas/tests/tslibs/test_array_to_datetime.py::test_parsing_timezone_offsets[01-01-2013' 'pandas/tests/tslibs/test_array_to_datetime.py::test_datetime_subclass[SubDatetime]' pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_homogeoneous_datetimes 'pandas/tests/tslibs/test_array_to_datetime.py::test_datetime_subclass[datetime]' pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_homogeoneous_date_objects 'pandas/tests/tslibs/test_array_to_datetime.py::TestArrayToDatetimeResolutionInference::test_infer_with_nat_int_float_str[nan]' 'pandas/tests/tslibs/test_array_to_datetime.py::test_parsing_timezone_offsets[12-31-2012'
: '>>>>> End Test Output'
git checkout fc37c83c2deb59253ae2d10ca631b6a1242cfdcb -- pandas/tests/tslibs/test_array_to_datetime.py 2>/dev/null || true
