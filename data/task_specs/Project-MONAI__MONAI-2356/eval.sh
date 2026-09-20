#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e6aa268e093434688907324cfe5d885c4d6ad9b4 -- tests/test_generate_param_groups.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_generate_param_groups.py b/tests/test_generate_param_groups.py
--- a/tests/test_generate_param_groups.py
+++ b/tests/test_generate_param_groups.py
@@ -25,6 +25,7 @@
         "lr_values": [1],
     },
     (1, 100),
+    [5, 21],
 ]
 
 TEST_CASE_2 = [
@@ -34,6 +35,7 @@
         "lr_values": [1, 2, 3],
     },
     (1, 2, 3, 100),
+    [5, 16, 5, 0],
 ]
 
 TEST_CASE_3 = [
@@ -43,15 +45,17 @@
         "lr_values": [1],
     },
     (1, 100),
+    [2, 24],
 ]
 
 TEST_CASE_4 = [
     {
-        "layer_matches": [lambda x: x.model[-1], lambda x: "conv.weight" in x],
+        "layer_matches": [lambda x: x.model[0], lambda x: "2.0.conv" in x[0]],
         "match_types": ["select", "filter"],
         "lr_values": [1, 2],
     },
     (1, 2, 100),
+    [5, 4, 17],
 ]
 
 TEST_CASE_5 = [
@@ -62,12 +66,24 @@
         "include_others": False,
     },
     (1),
+    [5],
+]
+
+TEST_CASE_6 = [
+    {
+        "layer_matches": [lambda x: "weight" in x[0]],
+        "match_types": ["filter"],
+        "lr_values": [1],
+        "include_others": True,
+    },
+    (1),
+    [16, 10],
 ]
 
 
 class TestGenerateParamGroups(unittest.TestCase):
-    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4, TEST_CASE_5])
-    def test_lr_values(self, input_param, expected_values):
+    @parameterized.expand([TEST_CASE_1, TEST_CASE_2, TEST_CASE_3, TEST_CASE_4, TEST_CASE_5, TEST_CASE_6])
+    def test_lr_values(self, input_param, expected_values, expected_groups):
         device = "cuda" if torch.cuda.is_available() else "cpu"
         net = Unet(
             dimensions=3,
@@ -85,7 +101,7 @@ def test_lr_values(self, input_param, expected_values):
             torch.testing.assert_allclose(param_group["lr"], value)
 
         n = [len(p["params"]) for p in params]
-        assert sum(n) == 26 or all(n), "should have either full model or non-empty subsets."
+        self.assertListEqual(n, expected_groups)
 
     def test_wrong(self):
         """overlapped"""

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_generate_param_groups.py::TestGenerateParamGroups::test_lr_values_3 tests/test_generate_param_groups.py::TestGenerateParamGroups::test_lr_values_5 tests/test_generate_param_groups.py::TestGenerateParamGroups::test_lr_values_2 tests/test_generate_param_groups.py::TestGenerateParamGroups::test_wrong tests/test_generate_param_groups.py::TestGenerateParamGroups::test_lr_values_1 tests/test_generate_param_groups.py::TestGenerateParamGroups::test_lr_values_4 tests/test_generate_param_groups.py::TestGenerateParamGroups::test_lr_values_0
: '>>>>> End Test Output'
git checkout e6aa268e093434688907324cfe5d885c4d6ad9b4 -- tests/test_generate_param_groups.py 2>/dev/null || true
