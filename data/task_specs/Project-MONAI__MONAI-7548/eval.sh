#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 95f69dea3d2ff9fb3d0695d922213aefaf5f0c39 -- tests/test_perceptual_loss.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_perceptual_loss.py b/tests/test_perceptual_loss.py
--- a/tests/test_perceptual_loss.py
+++ b/tests/test_perceptual_loss.py
@@ -40,6 +40,11 @@
         (2, 1, 64, 64, 64),
         (2, 1, 64, 64, 64),
     ],
+    [
+        {"spatial_dims": 3, "network_type": "medicalnet_resnet50_23datasets", "is_fake_3d": False},
+        (2, 1, 64, 64, 64),
+        (2, 1, 64, 64, 64),
+    ],
     [
         {"spatial_dims": 3, "network_type": "resnet50", "is_fake_3d": True, "pretrained": True, "fake_3d_ratio": 0.2},
         (2, 1, 64, 64, 64),

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_perceptual_loss.py::TestPerceptualLoss::test_shape_6 tests/test_perceptual_loss.py::TestPerceptualLoss::test_identical_input_6 tests/test_perceptual_loss.py::TestPerceptualLoss::test_identical_input_1 tests/test_perceptual_loss.py::TestPerceptualLoss::test_medicalnet_on_2d_data tests/test_perceptual_loss.py::TestPerceptualLoss::test_shape_2 tests/test_perceptual_loss.py::TestPerceptualLoss::test_shape_4 tests/test_perceptual_loss.py::TestPerceptualLoss::test_shape_1 tests/test_perceptual_loss.py::TestPerceptualLoss::test_1d tests/test_perceptual_loss.py::TestPerceptualLoss::test_shape_5 tests/test_perceptual_loss.py::TestPerceptualLoss::test_identical_input_3 tests/test_perceptual_loss.py::TestPerceptualLoss::test_different_shape tests/test_perceptual_loss.py::TestPerceptualLoss::test_identical_input_4 tests/test_perceptual_loss.py::TestPerceptualLoss::test_identical_input_2 tests/test_perceptual_loss.py::TestPerceptualLoss::test_identical_input_5 tests/test_perceptual_loss.py::TestPerceptualLoss::test_shape_3 tests/test_perceptual_loss.py::TestPerceptualLoss::test_identical_input_7 tests/test_perceptual_loss.py::TestPerceptualLoss::test_shape_0 tests/test_perceptual_loss.py::TestPerceptualLoss::test_identical_input_0 tests/test_perceptual_loss.py::TestPerceptualLoss::test_shape_7
: '>>>>> End Test Output'
git checkout 95f69dea3d2ff9fb3d0695d922213aefaf5f0c39 -- tests/test_perceptual_loss.py 2>/dev/null || true
