#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout cb2a40dd0ac1916b6dae0e8b2690e36ce36c4275 -- tests/test_iot/test_iot_search.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_iot/test_iot_search.py b/tests/test_iot/test_iot_search.py
--- a/tests/test_iot/test_iot_search.py
+++ b/tests/test_iot/test_iot_search.py
@@ -22,11 +22,15 @@ def test_search_things(query_string, results):
         client.create_thing(thingName=name)
 
     resp = client.search_index(queryString=query_string)
-    resp.should.have.key("thingGroups").equals([])
-    resp.should.have.key("things").length_of(len(results))
+    assert resp["thingGroups"] == []
+    assert len(resp["things"]) == len(results)
 
     thing_names = [t["thingName"] for t in resp["things"]]
-    set(thing_names).should.equal(results)
+    assert set(thing_names) == results
+
+    for thing in resp["things"]:
+        del thing["connectivity"]["timestamp"]
+        assert thing["connectivity"] == {"connected": True}
 
 
 @mock_iot

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/test_iot/test_iot_search.py::test_search_things[thingName:ab?-results3]' 'tests/test_iot/test_iot_search.py::test_search_things[abc-results0]' 'tests/test_iot/test_iot_search.py::test_search_things[thingName:abc-results1]' 'tests/test_iot/test_iot_search.py::test_search_things[*-results4]' 'tests/test_iot/test_iot_search.py::test_search_things[thingName:ab*-results2]'
: '>>>>> End Test Output'
git checkout cb2a40dd0ac1916b6dae0e8b2690e36ce36c4275 -- tests/test_iot/test_iot_search.py 2>/dev/null || true
