#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout cd1e7f3fb4a77a9958d71de7b326323c2f33336b -- tests/test_rand_elastic_2d.py tests/test_rand_elasticd_2d.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_rand_elastic_2d.py b/tests/test_rand_elastic_2d.py
--- a/tests/test_rand_elastic_2d.py
+++ b/tests/test_rand_elastic_2d.py
@@ -53,9 +53,9 @@
         {"img": torch.arange(27).reshape((3, 3, 3))},
         torch.tensor(
             [
-                [[2.1070, 2.0056], [5.6450, 5.8149]],
-                [[11.1070, 11.0056], [14.6450, 14.8149]],
-                [[20.1070, 20.0056], [23.6450, 23.8149]],
+                [[3.0793, 2.6141], [4.0568, 5.9978]],
+                [[12.0793, 11.6141], [13.0568, 14.9978]],
+                [[21.0793, 20.6141], [22.0568, 23.9978]],
             ]
         ),
     ],
diff --git a/tests/test_rand_elasticd_2d.py b/tests/test_rand_elasticd_2d.py
--- a/tests/test_rand_elasticd_2d.py
+++ b/tests/test_rand_elasticd_2d.py
@@ -79,9 +79,9 @@
         {"img": torch.arange(27).reshape((3, 3, 3)), "seg": torch.arange(27).reshape((3, 3, 3))},
         torch.tensor(
             [
-                [[2.1070, 2.0056], [5.6450, 5.8149]],
-                [[11.1070, 11.0056], [14.6450, 14.8149]],
-                [[20.1070, 20.0056], [23.6450, 23.8149]],
+                [[3.0793, 2.6141], [4.0568, 5.9978]],
+                [[12.0793, 11.6141], [13.0568, 14.9978]],
+                [[21.0793, 20.6141], [22.0568, 23.9978]],
             ]
         ),
     ],

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_rand_elasticd_2d.py::TestRand2DElasticd::test_rand_2d_elasticd_3 tests/test_rand_elastic_2d.py::TestRand2DElastic::test_rand_2d_elastic_3 tests/test_rand_elasticd_2d.py::TestRand2DElasticd::test_rand_2d_elasticd_2 tests/test_rand_elastic_2d.py::TestRand2DElastic::test_rand_2d_elastic_2 tests/test_rand_elasticd_2d.py::TestRand2DElasticd::test_rand_2d_elasticd_0 tests/test_rand_elastic_2d.py::TestRand2DElastic::test_rand_2d_elastic_1 tests/test_rand_elastic_2d.py::TestRand2DElastic::test_rand_2d_elastic_4 tests/test_rand_elastic_2d.py::TestRand2DElastic::test_rand_2d_elastic_0 tests/test_rand_elasticd_2d.py::TestRand2DElasticd::test_rand_2d_elasticd_1 tests/test_rand_elasticd_2d.py::TestRand2DElasticd::test_rand_2d_elasticd_4 tests/test_rand_elasticd_2d.py::TestRand2DElasticd::test_rand_2d_elasticd_5
: '>>>>> End Test Output'
git checkout cd1e7f3fb4a77a9958d71de7b326323c2f33336b -- tests/test_rand_elastic_2d.py tests/test_rand_elasticd_2d.py 2>/dev/null || true
