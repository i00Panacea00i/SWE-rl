#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout c319ca8ff31aa980a045f1b913fb2eb22aadb080 -- tests/test_unetr.py tests/test_vit.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_unetr.py b/tests/test_unetr.py
--- a/tests/test_unetr.py
+++ b/tests/test_unetr.py
@@ -16,6 +16,7 @@
 
 from monai.networks import eval_mode
 from monai.networks.nets.unetr import UNETR
+from tests.utils import SkipIfBeforePyTorchVersion, test_script_save
 
 TEST_CASE_UNETR = []
 for dropout_rate in [0.4]:
@@ -52,7 +53,7 @@
                                             TEST_CASE_UNETR.append(test_case)
 
 
-class TestPatchEmbeddingBlock(unittest.TestCase):
+class TestUNETR(unittest.TestCase):
     @parameterized.expand(TEST_CASE_UNETR)
     def test_shape(self, input_param, input_shape, expected_shape):
         net = UNETR(**input_param)
@@ -117,6 +118,17 @@ def test_ill_arg(self):
                 dropout_rate=0.2,
             )
 
+    @parameterized.expand(TEST_CASE_UNETR)
+    @SkipIfBeforePyTorchVersion((1, 9))
+    def test_script(self, input_param, input_shape, _):
+        net = UNETR(**(input_param))
+        net.eval()
+        with torch.no_grad():
+            torch.jit.script(net)
+
+        test_data = torch.randn(input_shape)
+        test_script_save(net, test_data)
+
 
 if __name__ == "__main__":
     unittest.main()
diff --git a/tests/test_vit.py b/tests/test_vit.py
--- a/tests/test_vit.py
+++ b/tests/test_vit.py
@@ -55,7 +55,7 @@
                                                 TEST_CASE_Vit.append(test_case)
 
 
-class TestPatchEmbeddingBlock(unittest.TestCase):
+class TestViT(unittest.TestCase):
     @parameterized.expand(TEST_CASE_Vit)
     def test_shape(self, input_param, input_shape, expected_shape):
         net = ViT(**input_param)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_unetr.py::TestUNETR::test_script_0 tests/test_unetr.py::TestUNETR::test_script_1 tests/test_unetr.py::TestUNETR::test_script_2 tests/test_unetr.py::TestUNETR::test_script_3 tests/test_vit.py::TestViT::test_shape_14 tests/test_vit.py::TestViT::test_shape_02 tests/test_vit.py::TestViT::test_script_15 tests/test_vit.py::TestViT::test_script_12 tests/test_vit.py::TestViT::test_shape_03 tests/test_vit.py::TestViT::test_ill_arg tests/test_vit.py::TestViT::test_script_06 tests/test_vit.py::TestViT::test_shape_12 tests/test_vit.py::TestViT::test_script_05 tests/test_vit.py::TestViT::test_script_02 tests/test_vit.py::TestViT::test_shape_06 tests/test_vit.py::TestViT::test_shape_15 tests/test_vit.py::TestViT::test_script_11 tests/test_vit.py::TestViT::test_shape_09 tests/test_vit.py::TestViT::test_script_14 tests/test_vit.py::TestViT::test_script_03 tests/test_vit.py::TestViT::test_shape_11 tests/test_unetr.py::TestUNETR::test_shape_3 tests/test_vit.py::TestViT::test_shape_13 tests/test_vit.py::TestViT::test_script_08 tests/test_vit.py::TestViT::test_script_04 tests/test_vit.py::TestViT::test_script_00 tests/test_vit.py::TestViT::test_shape_08 tests/test_unetr.py::TestUNETR::test_shape_1 tests/test_vit.py::TestViT::test_script_01 tests/test_vit.py::TestViT::test_script_10 tests/test_vit.py::TestViT::test_script_09 tests/test_vit.py::TestViT::test_shape_10 tests/test_vit.py::TestViT::test_script_07 tests/test_vit.py::TestViT::test_shape_07 tests/test_unetr.py::TestUNETR::test_shape_0 tests/test_vit.py::TestViT::test_shape_04 tests/test_unetr.py::TestUNETR::test_shape_2 tests/test_vit.py::TestViT::test_shape_01 tests/test_vit.py::TestViT::test_shape_00 tests/test_vit.py::TestViT::test_script_13 tests/test_unetr.py::TestUNETR::test_ill_arg tests/test_vit.py::TestViT::test_shape_05
: '>>>>> End Test Output'
git checkout c319ca8ff31aa980a045f1b913fb2eb22aadb080 -- tests/test_unetr.py tests/test_vit.py 2>/dev/null || true
