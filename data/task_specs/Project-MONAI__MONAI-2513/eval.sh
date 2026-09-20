#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 0711e0421afc16da378ffe7e348578ff2b3881f2 -- tests/test_focal_loss.py tests/test_masked_loss.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_focal_loss.py b/tests/test_focal_loss.py
--- a/tests/test_focal_loss.py
+++ b/tests/test_focal_loss.py
@@ -22,9 +22,9 @@
 
 class TestFocalLoss(unittest.TestCase):
     def test_consistency_with_cross_entropy_2d(self):
-        # For gamma=0 the focal loss reduces to the cross entropy loss
-        focal_loss = FocalLoss(to_onehot_y=True, gamma=0.0, reduction="mean", weight=1.0)
-        ce = nn.CrossEntropyLoss(reduction="mean")
+        """For gamma=0 the focal loss reduces to the cross entropy loss"""
+        focal_loss = FocalLoss(to_onehot_y=False, gamma=0.0, reduction="mean", weight=1.0)
+        ce = nn.BCEWithLogitsLoss(reduction="mean")
         max_error = 0
         class_num = 10
         batch_size = 128
@@ -32,12 +32,12 @@ def test_consistency_with_cross_entropy_2d(self):
             # Create a random tensor of shape (batch_size, class_num, 8, 4)
             x = torch.rand(batch_size, class_num, 8, 4, requires_grad=True)
             # Create a random batch of classes
-            l = torch.randint(low=0, high=class_num, size=(batch_size, 1, 8, 4))
+            l = torch.randint(low=0, high=2, size=(batch_size, class_num, 8, 4)).float()
             if torch.cuda.is_available():
                 x = x.cuda()
                 l = l.cuda()
             output0 = focal_loss(x, l)
-            output1 = ce(x, l[:, 0]) / class_num
+            output1 = ce(x, l)
             a = float(output0.cpu().detach())
             b = float(output1.cpu().detach())
             if abs(a - b) > max_error:
@@ -45,9 +45,9 @@ def test_consistency_with_cross_entropy_2d(self):
         self.assertAlmostEqual(max_error, 0.0, places=3)
 
     def test_consistency_with_cross_entropy_2d_onehot_label(self):
-        # For gamma=0 the focal loss reduces to the cross entropy loss
-        focal_loss = FocalLoss(to_onehot_y=False, gamma=0.0, reduction="mean")
-        ce = nn.CrossEntropyLoss(reduction="mean")
+        """For gamma=0 the focal loss reduces to the cross entropy loss"""
+        focal_loss = FocalLoss(to_onehot_y=True, gamma=0.0, reduction="mean")
+        ce = nn.BCEWithLogitsLoss(reduction="mean")
         max_error = 0
         class_num = 10
         batch_size = 128
@@ -59,8 +59,8 @@ def test_consistency_with_cross_entropy_2d_onehot_label(self):
             if torch.cuda.is_available():
                 x = x.cuda()
                 l = l.cuda()
-            output0 = focal_loss(x, one_hot(l, num_classes=class_num))
-            output1 = ce(x, l[:, 0]) / class_num
+            output0 = focal_loss(x, l)
+            output1 = ce(x, one_hot(l, num_classes=class_num))
             a = float(output0.cpu().detach())
             b = float(output1.cpu().detach())
             if abs(a - b) > max_error:
@@ -68,9 +68,9 @@ def test_consistency_with_cross_entropy_2d_onehot_label(self):
         self.assertAlmostEqual(max_error, 0.0, places=3)
 
     def test_consistency_with_cross_entropy_classification(self):
-        # for gamma=0 the focal loss reduces to the cross entropy loss
+        """for gamma=0 the focal loss reduces to the cross entropy loss"""
         focal_loss = FocalLoss(to_onehot_y=True, gamma=0.0, reduction="mean")
-        ce = nn.CrossEntropyLoss(reduction="mean")
+        ce = nn.BCEWithLogitsLoss(reduction="mean")
         max_error = 0
         class_num = 10
         batch_size = 128
@@ -84,19 +84,43 @@ def test_consistency_with_cross_entropy_classification(self):
                 x = x.cuda()
                 l = l.cuda()
             output0 = focal_loss(x, l)
-            output1 = ce(x, l[:, 0]) / class_num
+            output1 = ce(x, one_hot(l, num_classes=class_num))
             a = float(output0.cpu().detach())
             b = float(output1.cpu().detach())
             if abs(a - b) > max_error:
                 max_error = abs(a - b)
         self.assertAlmostEqual(max_error, 0.0, places=3)
 
+    def test_consistency_with_cross_entropy_classification_01(self):
+        # for gamma=0.1 the focal loss differs from the cross entropy loss
+        focal_loss = FocalLoss(to_onehot_y=True, gamma=0.1, reduction="mean")
+        ce = nn.BCEWithLogitsLoss(reduction="mean")
+        max_error = 0
+        class_num = 10
+        batch_size = 128
+        for _ in range(100):
+            # Create a random scores tensor of shape (batch_size, class_num)
+            x = torch.rand(batch_size, class_num, requires_grad=True)
+            # Create a random batch of classes
+            l = torch.randint(low=0, high=class_num, size=(batch_size, 1))
+            l = l.long()
+            if torch.cuda.is_available():
+                x = x.cuda()
+                l = l.cuda()
+            output0 = focal_loss(x, l)
+            output1 = ce(x, one_hot(l, num_classes=class_num))
+            a = float(output0.cpu().detach())
+            b = float(output1.cpu().detach())
+            if abs(a - b) > max_error:
+                max_error = abs(a - b)
+        self.assertNotAlmostEqual(max_error, 0.0, places=3)
+
     def test_bin_seg_2d(self):
         # define 2d examples
         target = torch.tensor([[0, 0, 0, 0], [0, 1, 1, 0], [0, 1, 1, 0], [0, 0, 0, 0]])
         # add another dimension corresponding to the batch (batch size = 1 here)
         target = target.unsqueeze(0)  # shape (1, H, W)
-        pred_very_good = 1000 * F.one_hot(target, num_classes=2).permute(0, 3, 1, 2).float()
+        pred_very_good = 100 * F.one_hot(target, num_classes=2).permute(0, 3, 1, 2).float() - 50.0
 
         # initialize the mean dice loss
         loss = FocalLoss(to_onehot_y=True)
@@ -112,7 +136,7 @@ def test_empty_class_2d(self):
         target = torch.tensor([[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
         # add another dimension corresponding to the batch (batch size = 1 here)
         target = target.unsqueeze(0)  # shape (1, H, W)
-        pred_very_good = 1000 * F.one_hot(target, num_classes=num_classes).permute(0, 3, 1, 2).float()
+        pred_very_good = 1000 * F.one_hot(target, num_classes=num_classes).permute(0, 3, 1, 2).float() - 500.0
 
         # initialize the mean dice loss
         loss = FocalLoss(to_onehot_y=True)
@@ -128,7 +152,7 @@ def test_multi_class_seg_2d(self):
         target = torch.tensor([[0, 0, 0, 0], [0, 1, 2, 0], [0, 3, 4, 0], [0, 0, 0, 0]])
         # add another dimension corresponding to the batch (batch size = 1 here)
         target = target.unsqueeze(0)  # shape (1, H, W)
-        pred_very_good = 1000 * F.one_hot(target, num_classes=num_classes).permute(0, 3, 1, 2).float()
+        pred_very_good = 1000 * F.one_hot(target, num_classes=num_classes).permute(0, 3, 1, 2).float() - 500.0
         # initialize the mean dice loss
         loss = FocalLoss(to_onehot_y=True)
         loss_onehot = FocalLoss(to_onehot_y=False)
@@ -159,7 +183,7 @@ def test_bin_seg_3d(self):
         # add another dimension corresponding to the batch (batch size = 1 here)
         target = target.unsqueeze(0)  # shape (1, H, W, D)
         target_one_hot = F.one_hot(target, num_classes=num_classes).permute(0, 4, 1, 2, 3)  # test one hot
-        pred_very_good = 1000 * F.one_hot(target, num_classes=num_classes).permute(0, 4, 1, 2, 3).float()
+        pred_very_good = 1000 * F.one_hot(target, num_classes=num_classes).permute(0, 4, 1, 2, 3).float() - 500.0
 
         # initialize the mean dice loss
         loss = FocalLoss(to_onehot_y=True)
@@ -173,6 +197,19 @@ def test_bin_seg_3d(self):
         focal_loss_good = float(loss_onehot(pred_very_good, target_one_hot).cpu())
         self.assertAlmostEqual(focal_loss_good, 0.0, places=3)
 
+    def test_foreground(self):
+        background = torch.ones(1, 1, 5, 5)
+        foreground = torch.zeros(1, 1, 5, 5)
+        target = torch.cat((background, foreground), dim=1)
+        input = torch.cat((background, foreground), dim=1)
+        target[:, 0, 2, 2] = 0
+        target[:, 1, 2, 2] = 1
+
+        fgbg = FocalLoss(to_onehot_y=False, include_background=True)(input, target)
+        fg = FocalLoss(to_onehot_y=False, include_background=False)(input, target)
+        self.assertAlmostEqual(float(fgbg.cpu()), 0.1116, places=3)
+        self.assertAlmostEqual(float(fg.cpu()), 0.1733, places=3)
+
     def test_ill_opts(self):
         chn_input = torch.ones((1, 2, 3))
         chn_target = torch.ones((1, 2, 3))
@@ -182,7 +219,7 @@ def test_ill_opts(self):
     def test_ill_shape(self):
         chn_input = torch.ones((1, 2, 3))
         chn_target = torch.ones((1, 3))
-        with self.assertRaisesRegex(AssertionError, ""):
+        with self.assertRaisesRegex(ValueError, ""):
             FocalLoss(reduction="mean")(chn_input, chn_target)
 
     def test_ill_class_weight(self):
diff --git a/tests/test_masked_loss.py b/tests/test_masked_loss.py
--- a/tests/test_masked_loss.py
+++ b/tests/test_masked_loss.py
@@ -32,7 +32,7 @@
             "to_onehot_y": True,
             "reduction": "sum",
         },
-        [(12.105497, 18.805185), (10.636354, 6.3138)],
+        [(14.538666, 20.191753), (13.17672, 8.251623)],
     ],
 ]
 
@@ -50,7 +50,6 @@ def test_shape(self, input_param, expected_val):
         label = torch.randint(low=0, high=2, size=size)
         label = torch.argmax(label, dim=1, keepdim=True)
         pred = torch.randn(size)
-        print(label[0, 0, 0])
         result = MaskedLoss(**input_param)(pred, label, None)
         out = result.detach().cpu().numpy()
         checked = np.allclose(out, expected_val[0][0]) or np.allclose(out, expected_val[0][1])

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_focal_loss.py::TestFocalLoss::test_consistency_with_cross_entropy_2d_onehot_label tests/test_focal_loss.py::TestFocalLoss::test_consistency_with_cross_entropy_classification tests/test_focal_loss.py::TestFocalLoss::test_ill_shape tests/test_focal_loss.py::TestFocalLoss::test_consistency_with_cross_entropy_2d tests/test_focal_loss.py::TestFocalLoss::test_foreground tests/test_masked_loss.py::TestMaskedLoss::test_shape_0 tests/test_focal_loss.py::TestFocalLoss::test_script tests/test_focal_loss.py::TestFocalLoss::test_multi_class_seg_2d tests/test_focal_loss.py::TestFocalLoss::test_ill_class_weight tests/test_focal_loss.py::TestFocalLoss::test_empty_class_2d tests/test_masked_loss.py::TestMaskedLoss::test_ill_opts tests/test_masked_loss.py::TestMaskedLoss::test_script tests/test_focal_loss.py::TestFocalLoss::test_bin_seg_3d tests/test_focal_loss.py::TestFocalLoss::test_consistency_with_cross_entropy_classification_01 tests/test_focal_loss.py::TestFocalLoss::test_ill_opts tests/test_focal_loss.py::TestFocalLoss::test_bin_seg_2d
: '>>>>> End Test Output'
git checkout 0711e0421afc16da378ffe7e348578ff2b3881f2 -- tests/test_focal_loss.py tests/test_masked_loss.py 2>/dev/null || true
