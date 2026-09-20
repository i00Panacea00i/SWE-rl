#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 9689abf834f004f49ca59c7fe931caf258da0af7 -- tests/test_sobel_gradient.py tests/test_sobel_gradientd.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_sobel_gradient.py b/tests/test_sobel_gradient.py
--- a/tests/test_sobel_gradient.py
+++ b/tests/test_sobel_gradient.py
@@ -17,8 +17,8 @@
 from monai.transforms import SobelGradients
 from tests.utils import assert_allclose
 
-IMAGE = torch.zeros(1, 1, 16, 16, dtype=torch.float32)
-IMAGE[0, 0, 8, :] = 1
+IMAGE = torch.zeros(1, 16, 16, dtype=torch.float32)
+IMAGE[0, 8, :] = 1
 OUTPUT_3x3 = torch.zeros(2, 16, 16, dtype=torch.float32)
 OUTPUT_3x3[0, 7, :] = 2.0
 OUTPUT_3x3[0, 9, :] = -2.0
@@ -28,7 +28,6 @@
 OUTPUT_3x3[1, 8, 0] = 1.0
 OUTPUT_3x3[1, 8, -1] = -1.0
 OUTPUT_3x3[1, 7, -1] = OUTPUT_3x3[1, 9, -1] = -0.5
-OUTPUT_3x3 = OUTPUT_3x3.unsqueeze(1)
 
 TEST_CASE_0 = [IMAGE, {"kernel_size": 3, "dtype": torch.float32}, OUTPUT_3x3]
 TEST_CASE_1 = [IMAGE, {"kernel_size": 3, "dtype": torch.float64}, OUTPUT_3x3]
diff --git a/tests/test_sobel_gradientd.py b/tests/test_sobel_gradientd.py
--- a/tests/test_sobel_gradientd.py
+++ b/tests/test_sobel_gradientd.py
@@ -17,8 +17,8 @@
 from monai.transforms import SobelGradientsd
 from tests.utils import assert_allclose
 
-IMAGE = torch.zeros(1, 1, 16, 16, dtype=torch.float32)
-IMAGE[0, 0, 8, :] = 1
+IMAGE = torch.zeros(1, 16, 16, dtype=torch.float32)
+IMAGE[0, 8, :] = 1
 OUTPUT_3x3 = torch.zeros(2, 16, 16, dtype=torch.float32)
 OUTPUT_3x3[0, 7, :] = 2.0
 OUTPUT_3x3[0, 9, :] = -2.0
@@ -28,7 +28,6 @@
 OUTPUT_3x3[1, 8, 0] = 1.0
 OUTPUT_3x3[1, 8, -1] = -1.0
 OUTPUT_3x3[1, 7, -1] = OUTPUT_3x3[1, 9, -1] = -0.5
-OUTPUT_3x3 = OUTPUT_3x3.unsqueeze(1)
 
 TEST_CASE_0 = [{"image": IMAGE}, {"keys": "image", "kernel_size": 3, "dtype": torch.float32}, {"image": OUTPUT_3x3}]
 TEST_CASE_1 = [{"image": IMAGE}, {"keys": "image", "kernel_size": 3, "dtype": torch.float64}, {"image": OUTPUT_3x3}]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_sobel_gradientd.py::SobelGradientTests::test_sobel_gradients_0 tests/test_sobel_gradient.py::SobelGradientTests::test_sobel_gradients_0 tests/test_sobel_gradientd.py::SobelGradientTests::test_sobel_gradients_error_0 tests/test_sobel_gradientd.py::SobelGradientTests::test_sobel_kernels_1 tests/test_sobel_gradient.py::SobelGradientTests::test_sobel_gradients_error_0 tests/test_sobel_gradient.py::SobelGradientTests::test_sobel_kernels_2 tests/test_sobel_gradient.py::SobelGradientTests::test_sobel_kernels_0 tests/test_sobel_gradientd.py::SobelGradientTests::test_sobel_kernels_0 tests/test_sobel_gradientd.py::SobelGradientTests::test_sobel_kernels_2 tests/test_sobel_gradient.py::SobelGradientTests::test_sobel_kernels_1
: '>>>>> End Test Output'
git checkout 9689abf834f004f49ca59c7fe931caf258da0af7 -- tests/test_sobel_gradient.py tests/test_sobel_gradientd.py 2>/dev/null || true
