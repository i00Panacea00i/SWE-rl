#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout bdf5e1ec15724ecf4e3634955cf34a35843a3e3e -- tests/test_rand_histogram_shift.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_rand_histogram_shift.py b/tests/test_rand_histogram_shift.py
--- a/tests/test_rand_histogram_shift.py
+++ b/tests/test_rand_histogram_shift.py
@@ -44,6 +44,16 @@
         ]
     )
 
+WARN_TESTS = []
+for p in TEST_NDARRAYS:
+    WARN_TESTS.append(
+        [
+            {"num_control_points": 5, "prob": 1.0},
+            {"img": p(np.zeros(8).reshape((1, 2, 2, 2)))},
+            np.zeros(8).reshape((1, 2, 2, 2)),
+        ]
+    )
+
 
 class TestRandHistogramShift(unittest.TestCase):
     @parameterized.expand(TESTS)
@@ -71,6 +81,12 @@ def test_interp(self):
             self.assertEqual(yi.shape, (3, 2))
             assert_allclose(yi, array_type([[1.0, 5.0], [0.5, -0.5], [4.0, 5.0]]))
 
+    @parameterized.expand(WARN_TESTS)
+    def test_warn(self, input_param, input_data, expected_val):
+        with self.assertWarns(Warning):
+            result = RandHistogramShift(**input_param)(**input_data)
+            assert_allclose(result, expected_val, type_test="tensor")
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_warn_2 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_warn_0 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_warn_1 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_7 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_2 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_4 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_5 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_0 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_8 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_6 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_1 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_rand_histogram_shift_3 tests/test_rand_histogram_shift.py::TestRandHistogramShift::test_interp
: '>>>>> End Test Output'
git checkout bdf5e1ec15724ecf4e3634955cf34a35843a3e3e -- tests/test_rand_histogram_shift.py 2>/dev/null || true
