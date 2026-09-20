#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8f5c9924df73f6f3dbb222d6a1263d71b7abd0cd -- tests/test_bundle_ckpt_export.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_bundle_ckpt_export.py b/tests/test_bundle_ckpt_export.py
--- a/tests/test_bundle_ckpt_export.py
+++ b/tests/test_bundle_ckpt_export.py
@@ -9,6 +9,7 @@
 # See the License for the specific language governing permissions and
 # limitations under the License.
 
+import json
 import os
 import subprocess
 import tempfile
@@ -17,6 +18,7 @@
 from parameterized import parameterized
 
 from monai.bundle import ConfigParser
+from monai.data import load_net_with_metadata
 from monai.networks import save_state
 from tests.utils import skip_if_windows
 
@@ -33,7 +35,8 @@ def test_export(self, key_in_ckpt):
         config_file = os.path.join(os.path.dirname(__file__), "testing_data", "inference.json")
         with tempfile.TemporaryDirectory() as tempdir:
             def_args = {"meta_file": "will be replaced by `meta_file` arg"}
-            def_args_file = os.path.join(tempdir, "def_args.json")
+            def_args_file = os.path.join(tempdir, "def_args.yaml")
+
             ckpt_file = os.path.join(tempdir, "model.pt")
             ts_file = os.path.join(tempdir, "model.ts")
 
@@ -44,11 +47,16 @@ def test_export(self, key_in_ckpt):
             save_state(src=net if key_in_ckpt == "" else {key_in_ckpt: net}, path=ckpt_file)
 
             cmd = ["coverage", "run", "-m", "monai.bundle", "ckpt_export", "network_def", "--filepath", ts_file]
-            cmd += ["--meta_file", meta_file, "--config_file", config_file, "--ckpt_file", ckpt_file]
-            cmd += ["--key_in_ckpt", key_in_ckpt, "--args_file", def_args_file]
+            cmd += ["--meta_file", meta_file, "--config_file", f"['{config_file}','{def_args_file}']", "--ckpt_file"]
+            cmd += [ckpt_file, "--key_in_ckpt", key_in_ckpt, "--args_file", def_args_file]
             subprocess.check_call(cmd)
             self.assertTrue(os.path.exists(ts_file))
 
+            _, metadata, extra_files = load_net_with_metadata(ts_file, more_extra_files=["inference", "def_args"])
+            self.assertTrue("schema" in metadata)
+            self.assertTrue("meta_file" in json.loads(extra_files["def_args"]))
+            self.assertTrue("network_def" in json.loads(extra_files["inference"]))
+
 
 if __name__ == "__main__":
     unittest.main()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_bundle_ckpt_export.py::TestCKPTExport::test_export_1_model tests/test_bundle_ckpt_export.py::TestCKPTExport::test_export_0_
: '>>>>> End Test Output'
git checkout 8f5c9924df73f6f3dbb222d6a1263d71b7abd0cd -- tests/test_bundle_ckpt_export.py 2>/dev/null || true
