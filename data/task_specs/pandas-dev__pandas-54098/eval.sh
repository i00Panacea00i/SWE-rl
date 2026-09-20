#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 2f08999a537646ee9d9d698a3fd502ccebb3d79d -- pandas/tests/tslibs/test_timedeltas.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/tslibs/test_timedeltas.py b/pandas/tests/tslibs/test_timedeltas.py
index 2308aa27b60ab..4784a6d0d600d 100644
--- a/pandas/tests/tslibs/test_timedeltas.py
+++ b/pandas/tests/tslibs/test_timedeltas.py
@@ -76,7 +76,10 @@ def test_delta_to_nanoseconds_td64_MY_raises():
 def test_unsupported_td64_unit_raises(unit):
     # GH 52806
     with pytest.raises(
-        ValueError, match=f"cannot construct a Timedelta from a unit {unit}"
+        ValueError,
+        match=f"Unit {unit} is not supported. "
+        "Only unambiguous timedelta values durations are supported. "
+        "Allowed units are 'W', 'D', 'h', 'm', 's', 'ms', 'us', 'ns'",
     ):
         Timedelta(np.timedelta64(1, unit))
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'pandas/tests/tslibs/test_timedeltas.py::test_unsupported_td64_unit_raises[Y]' 'pandas/tests/tslibs/test_timedeltas.py::test_unsupported_td64_unit_raises[M]' 'pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds[obj2--420000000000.0]' pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds_error 'pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds[obj5-86400000000111.0]' 'pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds[obj4-111]' 'pandas/tests/tslibs/test_timedeltas.py::test_ints_to_pytimedelta[s]' 'pandas/tests/tslibs/test_timedeltas.py::test_ints_to_pytimedelta_unsupported[Y]' 'pandas/tests/tslibs/test_timedeltas.py::test_ints_to_pytimedelta[ms]' 'pandas/tests/tslibs/test_timedeltas.py::test_kwarg_assertion[kwargs2]' 'pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds[obj6-125]' pandas/tests/tslibs/test_timedeltas.py::TestArrayToTimedelta64::test_array_to_timedelta64_string_with_unit_2d_raises pandas/tests/tslibs/test_timedeltas.py::test_huge_nanoseconds_overflow 'pandas/tests/tslibs/test_timedeltas.py::test_ints_to_pytimedelta_unsupported[ps]' 'pandas/tests/tslibs/test_timedeltas.py::test_ints_to_pytimedelta[us]' pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds_td64_MY_raises 'pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds[obj3-1234]' 'pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds[obj0-1209600000000000.0]' 'pandas/tests/tslibs/test_timedeltas.py::test_ints_to_pytimedelta_unsupported[as]' pandas/tests/tslibs/test_timedeltas.py::TestArrayToTimedelta64::test_array_to_timedelta64_non_object_raises 'pandas/tests/tslibs/test_timedeltas.py::test_ints_to_pytimedelta_unsupported[fs]' 'pandas/tests/tslibs/test_timedeltas.py::test_ints_to_pytimedelta_unsupported[M]' 'pandas/tests/tslibs/test_timedeltas.py::test_delta_to_nanoseconds[obj1--420000000000.0]' 'pandas/tests/tslibs/test_timedeltas.py::test_kwarg_assertion[kwargs1]' 'pandas/tests/tslibs/test_timedeltas.py::test_kwarg_assertion[kwargs0]'
: '>>>>> End Test Output'
git checkout 2f08999a537646ee9d9d698a3fd502ccebb3d79d -- pandas/tests/tslibs/test_timedeltas.py 2>/dev/null || true
