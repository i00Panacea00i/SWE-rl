#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 01feacbb70700ced80d0ba9784fe2ea729d8b959 -- tests/test_ensure_type.py tests/test_ensure_typed.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_ensure_type.py b/tests/test_ensure_type.py
--- a/tests/test_ensure_type.py
+++ b/tests/test_ensure_type.py
@@ -36,7 +36,7 @@ def test_single_input(self):
             test_datas.append(test_datas[-1].cuda())
         for test_data in test_datas:
             for dtype in ("tensor", "numpy"):
-                result = EnsureType(data_type=dtype)(test_data)
+                result = EnsureType(data_type=dtype, device="cpu")(test_data)
                 self.assertTrue(isinstance(result, torch.Tensor if dtype == "tensor" else np.ndarray))
                 if isinstance(test_data, bool):
                     self.assertFalse(result)
diff --git a/tests/test_ensure_typed.py b/tests/test_ensure_typed.py
--- a/tests/test_ensure_typed.py
+++ b/tests/test_ensure_typed.py
@@ -75,7 +75,7 @@ def test_dict(self):
             "extra": None,
         }
         for dtype in ("tensor", "numpy"):
-            result = EnsureTyped(keys="data", data_type=dtype)({"data": test_data})["data"]
+            result = EnsureTyped(keys="data", data_type=dtype, device="cpu")({"data": test_data})["data"]
             self.assertTrue(isinstance(result, dict))
             self.assertTrue(isinstance(result["img"], torch.Tensor if dtype == "tensor" else np.ndarray))
             torch.testing.assert_allclose(result["img"], torch.as_tensor([1.0, 2.0]))

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_ensure_type.py::TestEnsureType::test_single_input tests/test_ensure_typed.py::TestEnsureTyped::test_dict tests/test_ensure_type.py::TestEnsureType::test_dict tests/test_ensure_type.py::TestEnsureType::test_array_input tests/test_ensure_typed.py::TestEnsureTyped::test_array_input tests/test_ensure_typed.py::TestEnsureTyped::test_string tests/test_ensure_type.py::TestEnsureType::test_list_tuple tests/test_ensure_typed.py::TestEnsureTyped::test_single_input tests/test_ensure_typed.py::TestEnsureTyped::test_list_tuple tests/test_ensure_type.py::TestEnsureType::test_string
: '>>>>> End Test Output'
git checkout 01feacbb70700ced80d0ba9784fe2ea729d8b959 -- tests/test_ensure_type.py tests/test_ensure_typed.py 2>/dev/null || true
