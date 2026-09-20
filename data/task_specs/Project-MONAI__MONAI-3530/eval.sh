#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 9caa1d0a2d130cd7ac76d101770ab84f03a5f5eb -- tests/test_one_of.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_one_of.py b/tests/test_one_of.py
--- a/tests/test_one_of.py
+++ b/tests/test_one_of.py
@@ -12,9 +12,18 @@
 import unittest
 from copy import deepcopy
 
+import numpy as np
 from parameterized import parameterized
 
-from monai.transforms import InvertibleTransform, OneOf, TraceableTransform, Transform
+from monai.transforms import (
+    InvertibleTransform,
+    OneOf,
+    RandScaleIntensityd,
+    RandShiftIntensityd,
+    Resized,
+    TraceableTransform,
+    Transform,
+)
 from monai.transforms.compose import Compose
 from monai.transforms.transform import MapTransform
 from monai.utils.enums import TraceKeys
@@ -139,32 +148,52 @@ def _match(a, b):
         _match(p, f)
 
     @parameterized.expand(TEST_INVERSES)
-    def test_inverse(self, transform, should_be_ok):
+    def test_inverse(self, transform, invertible):
         data = {k: (i + 1) * 10.0 for i, k in enumerate(KEYS)}
         fwd_data = transform(data)
-        if not should_be_ok:
-            with self.assertRaises(RuntimeError):
-                transform.inverse(fwd_data)
-            return
-
-        for k in KEYS:
-            t = fwd_data[TraceableTransform.trace_key(k)][-1]
-            # make sure the OneOf index was stored
-            self.assertEqual(t[TraceKeys.CLASS_NAME], OneOf.__name__)
-            # make sure index exists and is in bounds
-            self.assertTrue(0 <= t[TraceKeys.EXTRA_INFO]["index"] < len(transform))
+
+        if invertible:
+            for k in KEYS:
+                t = fwd_data[TraceableTransform.trace_key(k)][-1]
+                # make sure the OneOf index was stored
+                self.assertEqual(t[TraceKeys.CLASS_NAME], OneOf.__name__)
+                # make sure index exists and is in bounds
+                self.assertTrue(0 <= t[TraceKeys.EXTRA_INFO]["index"] < len(transform))
 
         # call the inverse
         fwd_inv_data = transform.inverse(fwd_data)
 
-        for k in KEYS:
-            # check transform was removed
-            self.assertTrue(
-                len(fwd_inv_data[TraceableTransform.trace_key(k)]) < len(fwd_data[TraceableTransform.trace_key(k)])
-            )
-            # check data is same as original (and different from forward)
-            self.assertEqual(fwd_inv_data[k], data[k])
-            self.assertNotEqual(fwd_inv_data[k], fwd_data[k])
+        if invertible:
+            for k in KEYS:
+                # check transform was removed
+                self.assertTrue(
+                    len(fwd_inv_data[TraceableTransform.trace_key(k)]) < len(fwd_data[TraceableTransform.trace_key(k)])
+                )
+                # check data is same as original (and different from forward)
+                self.assertEqual(fwd_inv_data[k], data[k])
+                self.assertNotEqual(fwd_inv_data[k], fwd_data[k])
+        else:
+            # if not invertible, should not change the data
+            self.assertDictEqual(fwd_data, fwd_inv_data)
+
+    def test_inverse_compose(self):
+        transform = Compose(
+            [
+                Resized(keys="img", spatial_size=[100, 100, 100]),
+                OneOf(
+                    [
+                        RandScaleIntensityd(keys="img", factors=0.5, prob=1.0),
+                        RandShiftIntensityd(keys="img", offsets=0.5, prob=1.0),
+                    ]
+                ),
+            ]
+        )
+        transform.set_random_state(seed=0)
+        result = transform({"img": np.ones((1, 101, 102, 103))})
+
+        result = transform.inverse(result)
+        # invert to the original spatial shape
+        self.assertTupleEqual(result["img"].shape, (1, 101, 102, 103))
 
     def test_one_of(self):
         p = OneOf((A(), B(), C()), (1, 2, 1))

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_one_of.py::TestOneOf::test_inverse_compose tests/test_one_of.py::TestOneOf::test_inverse_3 tests/test_one_of.py::TestOneOf::test_inverse_2 tests/test_one_of.py::TestOneOf::test_normalize_weights_0 tests/test_one_of.py::TestOneOf::test_inverse_0 tests/test_one_of.py::TestOneOf::test_inverse_1 tests/test_one_of.py::TestOneOf::test_no_weights_arg tests/test_one_of.py::TestOneOf::test_compose_flatten_does_not_affect_one_of tests/test_one_of.py::TestOneOf::test_len_and_flatten tests/test_one_of.py::TestOneOf::test_one_of
: '>>>>> End Test Output'
git checkout 9caa1d0a2d130cd7ac76d101770ab84f03a5f5eb -- tests/test_one_of.py 2>/dev/null || true
