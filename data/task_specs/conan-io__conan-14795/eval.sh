#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8f9d42daa184c1c30d57e8765b872668585b8926 -- conans/test/integration/configuration/requester_test.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/integration/configuration/requester_test.py b/conans/test/integration/configuration/requester_test.py
--- a/conans/test/integration/configuration/requester_test.py
+++ b/conans/test/integration/configuration/requester_test.py
@@ -22,25 +22,19 @@ def get(self, _, **kwargs):
 
 
 class ConanRequesterCacertPathTests(unittest.TestCase):
-
-    @staticmethod
-    def _create_requesters(cache_folder=None):
-        cache = ClientCache(cache_folder or temp_folder())
-        mock_requester = MockRequesterGet()
-        requester = ConanRequester(cache.new_config)
-        return requester, mock_requester, cache
-
     def test_default_no_verify(self):
-        requester, mocked_requester, _ = self._create_requesters()
+        mocked_requester = MockRequesterGet()
         with mock.patch("conans.client.rest.conan_requester.requests", mocked_requester):
+            requester = ConanRequester(ClientCache(temp_folder()).new_config)
             requester.get(url="aaa", verify=False)
-            self.assertEqual(mocked_requester.verify, False)
+            self.assertEqual(requester._http_requester.verify, False)
 
     def test_default_verify(self):
-        requester, mocked_requester, cache = self._create_requesters()
+        mocked_requester = MockRequesterGet()
         with mock.patch("conans.client.rest.conan_requester.requests", mocked_requester):
+            requester = ConanRequester(ClientCache(temp_folder()).new_config)
             requester.get(url="aaa", verify=True)
-            self.assertEqual(mocked_requester.verify, True)
+            self.assertEqual(requester._http_requester.verify, True)
 
     def test_cache_config(self):
         file_path = os.path.join(temp_folder(), "whatever_cacert")
@@ -51,7 +45,7 @@ def test_cache_config(self):
         with mock.patch("conans.client.rest.conan_requester.requests", mocked_requester):
             requester = ConanRequester(config)
             requester.get(url="bbbb", verify=True)
-        self.assertEqual(mocked_requester.verify, file_path)
+        self.assertEqual(requester._http_requester.verify, file_path)
 
 
 class ConanRequesterHeadersTests(unittest.TestCase):
@@ -62,9 +56,9 @@ def test_user_agent(self):
         with mock.patch("conans.client.rest.conan_requester.requests", mock_http_requester):
             requester = ConanRequester(cache.new_config)
             requester.get(url="aaa")
-            headers = mock_http_requester.get.call_args[1]["headers"]
+            headers = requester._http_requester.get.call_args[1]["headers"]
             self.assertIn("Conan/%s" % __version__, headers["User-Agent"])
 
             requester.get(url="aaa", headers={"User-Agent": "MyUserAgent"})
-            headers = mock_http_requester.get.call_args[1]["headers"]
+            headers = requester._http_requester.get.call_args[1]["headers"]
             self.assertEqual("MyUserAgent", headers["User-Agent"])

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail conans/test/integration/configuration/requester_test.py::ConanRequesterCacertPathTests::test_cache_config conans/test/integration/configuration/requester_test.py::ConanRequesterCacertPathTests::test_default_verify conans/test/integration/configuration/requester_test.py::ConanRequesterCacertPathTests::test_default_no_verify conans/test/integration/configuration/requester_test.py::ConanRequesterHeadersTests::test_user_agent
: '>>>>> End Test Output'
git checkout 8f9d42daa184c1c30d57e8765b872668585b8926 -- conans/test/integration/configuration/requester_test.py 2>/dev/null || true
