#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 7bf8d6b318e0b385802e181ace3432ae73cbf79b -- pandas/tests/tseries/holiday/test_federal.py pandas/tests/tseries/holiday/test_holiday.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/tseries/holiday/test_federal.py b/pandas/tests/tseries/holiday/test_federal.py
index 64c60d4e365e6..2565877f8a2a4 100644
--- a/pandas/tests/tseries/holiday/test_federal.py
+++ b/pandas/tests/tseries/holiday/test_federal.py
@@ -1,7 +1,11 @@
 from datetime import datetime
 
+from pandas import DatetimeIndex
+import pandas._testing as tm
+
 from pandas.tseries.holiday import (
     AbstractHolidayCalendar,
+    USFederalHolidayCalendar,
     USMartinLutherKingJr,
     USMemorialDay,
 )
@@ -36,3 +40,19 @@ class MemorialDay(AbstractHolidayCalendar):
         datetime(1978, 5, 29, 0, 0),
         datetime(1979, 5, 28, 0, 0),
     ]
+
+
+def test_federal_holiday_inconsistent_returntype():
+    # GH 49075 test case
+    # Instantiate two calendars to rule out _cache
+    cal1 = USFederalHolidayCalendar()
+    cal2 = USFederalHolidayCalendar()
+
+    results_2018 = cal1.holidays(start=datetime(2018, 8, 1), end=datetime(2018, 8, 31))
+    results_2019 = cal2.holidays(start=datetime(2019, 8, 1), end=datetime(2019, 8, 31))
+    expected_results = DatetimeIndex([], dtype="datetime64[ns]", freq=None)
+
+    # Check against expected results to ensure both date
+    # ranges generate expected results as per GH49075 submission
+    tm.assert_index_equal(results_2018, expected_results)
+    tm.assert_index_equal(results_2019, expected_results)
diff --git a/pandas/tests/tseries/holiday/test_holiday.py b/pandas/tests/tseries/holiday/test_holiday.py
index cefb2f86703b2..ee83ca144d38a 100644
--- a/pandas/tests/tseries/holiday/test_holiday.py
+++ b/pandas/tests/tseries/holiday/test_holiday.py
@@ -3,6 +3,7 @@
 import pytest
 from pytz import utc
 
+from pandas import DatetimeIndex
 import pandas._testing as tm
 
 from pandas.tseries.holiday import (
@@ -264,3 +265,49 @@ def test_both_offset_observance_raises():
             offset=[DateOffset(weekday=SA(4))],
             observance=next_monday,
         )
+
+
+def test_half_open_interval_with_observance():
+    # Prompted by GH 49075
+    # Check for holidays that have a half-open date interval where
+    # they have either a start_date or end_date defined along
+    # with a defined observance pattern to make sure that the return type
+    # for Holiday.dates() remains consistent before & after the year that
+    # marks the 'edge' of the half-open date interval.
+
+    holiday_1 = Holiday(
+        "Arbitrary Holiday - start 2022-03-14",
+        start_date=datetime(2022, 3, 14),
+        month=3,
+        day=14,
+        observance=next_monday,
+    )
+    holiday_2 = Holiday(
+        "Arbitrary Holiday 2 - end 2022-03-20",
+        end_date=datetime(2022, 3, 20),
+        month=3,
+        day=20,
+        observance=next_monday,
+    )
+
+    class TestHolidayCalendar(AbstractHolidayCalendar):
+        rules = [
+            USMartinLutherKingJr,
+            holiday_1,
+            holiday_2,
+            USLaborDay,
+        ]
+
+    start = Timestamp("2022-08-01")
+    end = Timestamp("2022-08-31")
+    year_offset = DateOffset(years=5)
+    expected_results = DatetimeIndex([], dtype="datetime64[ns]", freq=None)
+    test_cal = TestHolidayCalendar()
+
+    date_interval_low = test_cal.holidays(start - year_offset, end - year_offset)
+    date_window_edge = test_cal.holidays(start, end)
+    date_interval_high = test_cal.holidays(start + year_offset, end + year_offset)
+
+    tm.assert_index_equal(date_interval_low, expected_results)
+    tm.assert_index_equal(date_window_edge, expected_results)
+    tm.assert_index_equal(date_interval_high, expected_results)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail pandas/tests/tseries/holiday/test_federal.py::test_federal_holiday_inconsistent_returntype pandas/tests/tseries/holiday/test_holiday.py::test_half_open_interval_with_observance 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[New' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday7-2015-11-26-expected7]' 'pandas/tests/tseries/holiday/test_holiday.py::test_argument_types[<lambda>0]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday6-start6-expected6]' 'pandas/tests/tseries/holiday/test_holiday.py::test_argument_types[<lambda>1]' pandas/tests/tseries/holiday/test_holiday.py::test_get_calendar pandas/tests/tseries/holiday/test_federal.py::test_no_mlk_before_1986 'pandas/tests/tseries/holiday/test_holiday.py::test_holiday_dates[holiday0-start_date0-end_date0-expected0]' pandas/tests/tseries/holiday/test_holiday.py::test_both_offset_observance_raises 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday14-2015-04-06-expected14]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday16-2015-04-05-expected16]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday11-2015-02-16-expected11]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday13-2015-04-03-expected13]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holiday_dates[holiday2-2001-01-01-2008-03-03-expected2]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holiday_dates[holiday3-start_date3-end_date3-expected3]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holiday_dates[holiday1-2001-01-01-2003-03-03-expected1]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday9-2015-01-19-expected9]' 'pandas/tests/tseries/holiday/test_holiday.py::test_special_holidays[One-Time-kwargs0]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday4-start4-expected4]' 'pandas/tests/tseries/holiday/test_holiday.py::test_special_holidays[Range-kwargs1]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday3-2015-09-07-expected3]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holiday_dates[holiday4-start_date4-end_date4-expected4]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday2-start2-expected2]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[Christmas' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[Veterans' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday1-2015-05-25-expected1]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday5-2015-10-12-expected5]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[Independence' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday8-start8-expected8]' pandas/tests/tseries/holiday/test_federal.py::test_memorial_day 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday12-start12-expected12]' pandas/tests/tseries/holiday/test_holiday.py::test_factory 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[Juneteenth' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday0-start0-expected0]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holiday_dates[holiday5-start_date5-end_date5-expected5]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday15-start15-expected15]' 'pandas/tests/tseries/holiday/test_holiday.py::test_holidays_within_dates[holiday10-start10-expected10]'
: '>>>>> End Test Output'
git checkout 7bf8d6b318e0b385802e181ace3432ae73cbf79b -- pandas/tests/tseries/holiday/test_federal.py pandas/tests/tseries/holiday/test_holiday.py 2>/dev/null || true
