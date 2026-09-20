#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout ce6daf704af72fa7b124855580ad0c906b7f8f07 -- tests/test_one_of.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_one_of.py b/tests/test_one_of.py
--- a/tests/test_one_of.py
+++ b/tests/test_one_of.py
@@ -15,11 +15,15 @@
 import numpy as np
 from parameterized import parameterized
 
+from monai.data import MetaTensor
 from monai.transforms import (
     InvertibleTransform,
     OneOf,
+    RandScaleIntensity,
     RandScaleIntensityd,
+    RandShiftIntensity,
     RandShiftIntensityd,
+    Resize,
     Resized,
     TraceableTransform,
     Transform,
@@ -106,10 +110,10 @@ def __init__(self, keys):
 
 KEYS = ["x", "y"]
 TEST_INVERSES = [
-    (OneOf((InvA(KEYS), InvB(KEYS))), True),
-    (OneOf((OneOf((InvA(KEYS), InvB(KEYS))), OneOf((InvB(KEYS), InvA(KEYS))))), True),
-    (OneOf((Compose((InvA(KEYS), InvB(KEYS))), Compose((InvB(KEYS), InvA(KEYS))))), True),
-    (OneOf((NonInv(KEYS), NonInv(KEYS))), False),
+    (OneOf((InvA(KEYS), InvB(KEYS))), True, True),
+    (OneOf((OneOf((InvA(KEYS), InvB(KEYS))), OneOf((InvB(KEYS), InvA(KEYS))))), True, False),
+    (OneOf((Compose((InvA(KEYS), InvB(KEYS))), Compose((InvB(KEYS), InvA(KEYS))))), True, False),
+    (OneOf((NonInv(KEYS), NonInv(KEYS))), False, False),
 ]
 
 
@@ -148,13 +152,17 @@ def _match(a, b):
         _match(p, f)
 
     @parameterized.expand(TEST_INVERSES)
-    def test_inverse(self, transform, invertible):
-        data = {k: (i + 1) * 10.0 for i, k in enumerate(KEYS)}
+    def test_inverse(self, transform, invertible, use_metatensor):
+        data = {k: (i + 1) * 10.0 if not use_metatensor else MetaTensor((i + 1) * 10.0) for i, k in enumerate(KEYS)}
         fwd_data = transform(data)
 
         if invertible:
             for k in KEYS:
-                t = fwd_data[TraceableTransform.trace_key(k)][-1]
+                t = (
+                    fwd_data[TraceableTransform.trace_key(k)][-1]
+                    if not use_metatensor
+                    else fwd_data[k].applied_operations[-1]
+                )
                 # make sure the OneOf index was stored
                 self.assertEqual(t[TraceKeys.CLASS_NAME], OneOf.__name__)
                 # make sure index exists and is in bounds
@@ -166,9 +174,11 @@ def test_inverse(self, transform, invertible):
         if invertible:
             for k in KEYS:
                 # check transform was removed
-                self.assertTrue(
-                    len(fwd_inv_data[TraceableTransform.trace_key(k)]) < len(fwd_data[TraceableTransform.trace_key(k)])
-                )
+                if not use_metatensor:
+                    self.assertTrue(
+                        len(fwd_inv_data[TraceableTransform.trace_key(k)])
+                        < len(fwd_data[TraceableTransform.trace_key(k)])
+                    )
                 # check data is same as original (and different from forward)
                 self.assertEqual(fwd_inv_data[k], data[k])
                 self.assertNotEqual(fwd_inv_data[k], fwd_data[k])
@@ -186,15 +196,34 @@ def test_inverse_compose(self):
                         RandShiftIntensityd(keys="img", offsets=0.5, prob=1.0),
                     ]
                 ),
+                OneOf(
+                    [
+                        RandScaleIntensityd(keys="img", factors=0.5, prob=1.0),
+                        RandShiftIntensityd(keys="img", offsets=0.5, prob=1.0),
+                    ]
+                ),
             ]
         )
         transform.set_random_state(seed=0)
         result = transform({"img": np.ones((1, 101, 102, 103))})
-
         result = transform.inverse(result)
         # invert to the original spatial shape
         self.assertTupleEqual(result["img"].shape, (1, 101, 102, 103))
 
+    def test_inverse_metatensor(self):
+        transform = Compose(
+            [
+                Resize(spatial_size=[100, 100, 100]),
+                OneOf([RandScaleIntensity(factors=0.5, prob=1.0), RandShiftIntensity(offsets=0.5, prob=1.0)]),
+                OneOf([RandScaleIntensity(factors=0.5, prob=1.0), RandShiftIntensity(offsets=0.5, prob=1.0)]),
+            ]
+        )
+        transform.set_random_state(seed=0)
+        result = transform(np.ones((1, 101, 102, 103)))
+        self.assertTupleEqual(result.shape, (1, 100, 100, 100))
+        result = transform.inverse(result)
+        self.assertTupleEqual(result.shape, (1, 101, 102, 103))
+
     def test_one_of(self):
         p = OneOf((A(), B(), C()), (1, 2, 1))
         counts = [0] * 3

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_one_of.py::TestOneOf::test_inverse_metatensor tests/test_one_of.py::TestOneOf::test_inverse_0 tests/test_one_of.py::TestOneOf::test_inverse_2 tests/test_one_of.py::TestOneOf::test_normalize_weights_0 tests/test_one_of.py::TestOneOf::test_inverse_3 tests/test_one_of.py::TestOneOf::test_inverse_1 tests/test_one_of.py::TestOneOf::test_inverse_compose tests/test_one_of.py::TestOneOf::test_no_weights_arg tests/test_one_of.py::TestOneOf::test_compose_flatten_does_not_affect_one_of tests/test_one_of.py::TestOneOf::test_len_and_flatten tests/test_one_of.py::TestOneOf::test_one_of
: '>>>>> End Test Output'
git checkout ce6daf704af72fa7b124855580ad0c906b7f8f07 -- tests/test_one_of.py 2>/dev/null || true
