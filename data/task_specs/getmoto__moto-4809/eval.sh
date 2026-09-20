#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout f158f0e9859e96c71bc0201ec7558bb817aee7d8 -- tests/test_batch/test_batch_task_definition.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_batch/test_batch_task_definition.py b/tests/test_batch/test_batch_task_definition.py
--- a/tests/test_batch/test_batch_task_definition.py
+++ b/tests/test_batch/test_batch_task_definition.py
@@ -195,25 +195,20 @@ def register_job_def(batch_client, definition_name="sleep10", use_resource_reqs=
         container_properties.update(
             {
                 "resourceRequirements": [
-                    {"value": "1", "type": "VCPU"},
-                    {"value": str(random.randint(4, 128)), "type": "MEMORY"},
+                    {"value": "0.25", "type": "VCPU"},
+                    {"value": "512", "type": "MEMORY"},
                 ]
             }
         )
     else:
         container_properties.update(
-            {"memory": random.randint(4, 128), "vcpus": 1,}
+            {"memory": 128, "vcpus": 1,}
         )
 
     return batch_client.register_job_definition(
         jobDefinitionName=definition_name,
         type="container",
-        containerProperties={
-            "image": "busybox",
-            "vcpus": 1,
-            "memory": random.randint(4, 128),
-            "command": ["sleep", "10"],
-        },
+        containerProperties=container_properties,
     )
 
 

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/test_batch/test_batch_task_definition.py::test_delete_task_definition_by_name[True]' 'tests/test_batch/test_batch_task_definition.py::test_describe_task_definition[True]' 'tests/test_batch/test_batch_task_definition.py::test_register_task_definition[True]' 'tests/test_batch/test_batch_task_definition.py::test_delete_task_definition[True]' 'tests/test_batch/test_batch_task_definition.py::test_reregister_task_definition[True]' tests/test_batch/test_batch_task_definition.py::test_register_task_definition_with_tags 'tests/test_batch/test_batch_task_definition.py::test_reregister_task_definition[False]' 'tests/test_batch/test_batch_task_definition.py::test_describe_task_definition[False]' 'tests/test_batch/test_batch_task_definition.py::test_register_task_definition[False]' 'tests/test_batch/test_batch_task_definition.py::test_delete_task_definition_by_name[False]' 'tests/test_batch/test_batch_task_definition.py::test_delete_task_definition[False]'
: '>>>>> End Test Output'
git checkout f158f0e9859e96c71bc0201ec7558bb817aee7d8 -- tests/test_batch/test_batch_task_definition.py 2>/dev/null || true
