#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout e4b99e15353a86fc1f14b34ddbc337ff9cd759b0 -- tests/test_localnet.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_localnet.py b/tests/test_localnet.py
--- a/tests/test_localnet.py
+++ b/tests/test_localnet.py
@@ -65,6 +65,12 @@ def test_shape(self, input_param, input_shape, expected_shape):
             result = net(torch.randn(input_shape).to(device))
             self.assertEqual(result.shape, expected_shape)
 
+    @parameterized.expand(TEST_CASE_LOCALNET_2D + TEST_CASE_LOCALNET_3D)
+    def test_extract_levels(self, input_param, input_shape, expected_shape):
+        net = LocalNet(**input_param).to(device)
+        self.assertEqual(len(net.decode_deconvs), len(input_param["extract_levels"]) - 1)
+        self.assertEqual(len(net.decode_convs), len(input_param["extract_levels"]) - 1)
+
     def test_script(self):
         input_param, input_shape, _ = TEST_CASE_LOCALNET_2D[0]
         net = LocalNet(**input_param)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_localnet.py::TestLocalNet::test_extract_levels_0 tests/test_localnet.py::TestLocalNet::test_extract_levels_1 tests/test_localnet.py::TestLocalNet::test_script tests/test_localnet.py::TestLocalNet::test_shape_0 tests/test_localnet.py::TestLocalNet::test_shape_1
: '>>>>> End Test Output'
git checkout e4b99e15353a86fc1f14b34ddbc337ff9cd759b0 -- tests/test_localnet.py 2>/dev/null || true
