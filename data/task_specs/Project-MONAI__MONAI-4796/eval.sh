#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout c1eaf427ed2310483856e33e57e7b83d59c85b13 -- tests/test_handler_prob_map_producer.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_handler_prob_map_producer.py b/tests/test_handler_prob_map_producer.py
--- a/tests/test_handler_prob_map_producer.py
+++ b/tests/test_handler_prob_map_producer.py
@@ -36,9 +36,9 @@ def __init__(self, name, size):
                     "image": name,
                     ProbMapKeys.COUNT.value: size,
                     ProbMapKeys.SIZE.value: np.array([size, size]),
-                    ProbMapKeys.LOCATION.value: np.array([i, i]),
+                    ProbMapKeys.LOCATION.value: np.array([i, i + 1]),
                 }
-                for i in range(size)
+                for i in range(size - 1)
             ]
         )
         self.image_data = [
@@ -94,7 +94,8 @@ def inference(enging, batch):
         engine.run(data_loader)
 
         prob_map = np.load(os.path.join(output_dir, name + ".npy"))
-        self.assertListEqual(np.diag(prob_map).astype(int).tolist(), list(range(1, size + 1)))
+        self.assertListEqual(np.vstack(prob_map.nonzero()).T.tolist(), [[i, i + 1] for i in range(size - 1)])
+        self.assertListEqual(prob_map[prob_map.nonzero()].tolist(), [i + 1 for i in range(size - 1)])
 
 
 if __name__ == "__main__":

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_handler_prob_map_producer.py::TestHandlerProbMapGenerator::test_prob_map_generator_0_temp_image_inference_output_1 tests/test_handler_prob_map_producer.py::TestHandlerProbMapGenerator::test_prob_map_generator_2_temp_image_inference_output_3 tests/test_handler_prob_map_producer.py::TestHandlerProbMapGenerator::test_prob_map_generator_1_temp_image_inference_output_2
: '>>>>> End Test Output'
git checkout c1eaf427ed2310483856e33e57e7b83d59c85b13 -- tests/test_handler_prob_map_producer.py 2>/dev/null || true
