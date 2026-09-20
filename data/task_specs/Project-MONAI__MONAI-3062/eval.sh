#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 87e2ecdcfc77c9f41d4fb10626d8c6e3e302be57 -- tests/test_scale_intensity.py tests/test_scale_intensityd.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_scale_intensity.py b/tests/test_scale_intensity.py
--- a/tests/test_scale_intensity.py
+++ b/tests/test_scale_intensity.py
@@ -35,6 +35,18 @@ def test_factor_scale(self):
             expected = p((self.imt * (1 + 0.1)).astype(np.float32))
             assert_allclose(result, p(expected), rtol=1e-7, atol=0)
 
+    def test_channel_wise(self):
+        for p in TEST_NDARRAYS:
+            scaler = ScaleIntensity(minv=1.0, maxv=2.0, channel_wise=True)
+            data = p(self.imt)
+            result = scaler(data)
+            mina = self.imt.min()
+            maxa = self.imt.max()
+            for i, c in enumerate(data):
+                norm = (c - mina) / (maxa - mina)
+                expected = p((norm * (2.0 - 1.0)) + 1.0)
+                assert_allclose(result[i], expected, type_test=False, rtol=1e-7, atol=0)
+
 
 if __name__ == "__main__":
     unittest.main()
diff --git a/tests/test_scale_intensityd.py b/tests/test_scale_intensityd.py
--- a/tests/test_scale_intensityd.py
+++ b/tests/test_scale_intensityd.py
@@ -37,6 +37,19 @@ def test_factor_scale(self):
             expected = (self.imt * (1 + 0.1)).astype(np.float32)
             assert_allclose(result[key], p(expected))
 
+    def test_channel_wise(self):
+        key = "img"
+        for p in TEST_NDARRAYS:
+            scaler = ScaleIntensityd(keys=[key], minv=1.0, maxv=2.0, channel_wise=True)
+            data = p(self.imt)
+            result = scaler({key: data})
+            mina = self.imt.min()
+            maxa = self.imt.max()
+            for i, c in enumerate(data):
+                norm = (c - mina) / (maxa - mina)
+                expected = p((norm * (2.0 - 1.0)) + 1.0)
+                assert_allclose(result[key][i], expected, type_test=False, rtol=1e-7, atol=0)
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_scale_intensity.py::TestScaleIntensity::test_channel_wise tests/test_scale_intensityd.py::TestScaleIntensityd::test_channel_wise tests/test_scale_intensityd.py::TestScaleIntensityd::test_factor_scale tests/test_scale_intensity.py::TestScaleIntensity::test_range_scale tests/test_scale_intensity.py::TestScaleIntensity::test_factor_scale tests/test_scale_intensityd.py::TestScaleIntensityd::test_range_scale
: '>>>>> End Test Output'
git checkout 87e2ecdcfc77c9f41d4fb10626d8c6e3e302be57 -- tests/test_scale_intensity.py tests/test_scale_intensityd.py 2>/dev/null || true
