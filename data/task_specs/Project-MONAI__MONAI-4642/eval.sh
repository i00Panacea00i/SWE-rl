#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 99b9dd7cf0667113e56f0dd90d40699115048d59 -- tests/test_pad_collation.py tests/test_testtimeaugmentation.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_pad_collation.py b/tests/test_pad_collation.py
--- a/tests/test_pad_collation.py
+++ b/tests/test_pad_collation.py
@@ -98,9 +98,12 @@ def test_pad_collation(self, t_type, collate_method, transform):
         # check collation in forward direction
         for data in loader:
             if t_type == dict:
+                shapes = []
                 decollated_data = decollate_batch(data)
                 for d in decollated_data:
-                    PadListDataCollate.inverse(d)
+                    output = PadListDataCollate.inverse(d)
+                    shapes.append(output["image"].shape)
+                self.assertTrue(len(set(shapes)) > 1)  # inverted shapes must be different because of random xforms
 
 
 if __name__ == "__main__":
diff --git a/tests/test_testtimeaugmentation.py b/tests/test_testtimeaugmentation.py
--- a/tests/test_testtimeaugmentation.py
+++ b/tests/test_testtimeaugmentation.py
@@ -58,9 +58,7 @@ def get_data(num_examples, input_size, data_type=np.asarray, include_label=True)
         data = []
         for i in range(num_examples):
             im, label = custom_create_test_image_2d()
-            d = {}
-            d["image"] = data_type(im[:, i:])
-            d[PostFix.meta("image")] = {"affine": np.eye(4)}
+            d = {"image": data_type(im[:, i:])}
             if include_label:
                 d["label"] = data_type(label[:, i:])
                 d[PostFix.meta("label")] = {"affine": np.eye(4)}

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_pad_collation.py::TestPadCollation::test_pad_collation_09 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_00 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_03 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_01 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_08 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_10 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_11 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_02 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_15 tests/test_testtimeaugmentation.py::TestTestTimeAugmentation::test_test_time_augmentation tests/test_testtimeaugmentation.py::TestTestTimeAugmentation::test_warn_random_but_has_no_invertible tests/test_pad_collation.py::TestPadCollation::test_pad_collation_14 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_07 tests/test_testtimeaugmentation.py::TestTestTimeAugmentation::test_image_no_label tests/test_pad_collation.py::TestPadCollation::test_pad_collation_04 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_06 tests/test_testtimeaugmentation.py::TestTestTimeAugmentation::test_warn_random_but_all_not_invertible tests/test_pad_collation.py::TestPadCollation::test_pad_collation_12 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_13 tests/test_pad_collation.py::TestPadCollation::test_pad_collation_05 tests/test_testtimeaugmentation.py::TestTestTimeAugmentation::test_single_transform tests/test_testtimeaugmentation.py::TestTestTimeAugmentation::test_warn_non_random
: '>>>>> End Test Output'
git checkout 99b9dd7cf0667113e56f0dd90d40699115048d59 -- tests/test_pad_collation.py tests/test_testtimeaugmentation.py 2>/dev/null || true
