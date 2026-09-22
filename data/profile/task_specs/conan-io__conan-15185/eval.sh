#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 2e568138707a4d35a53e063a86af2aa6ee2793fb -- conans/test/integration/command/test_profile.py conans/test/unittests/model/profile_test.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/integration/command/test_profile.py b/conans/test/integration/command/test_profile.py
--- a/conans/test/integration/command/test_profile.py
+++ b/conans/test/integration/command/test_profile.py
@@ -133,9 +133,13 @@ def test_shorthand_syntax():
 
 def test_profile_show_json():
     c = TestClient()
-    c.save({"myprofilewin": "[settings]\nos=Windows",
+    c.save({"myprofilewin": "[settings]\nos=Windows\n[tool_requires]\nmytool/*:mytool/1.0",
             "myprofilelinux": "[settings]\nos=Linux"})
     c.run("profile show -pr:b=myprofilewin -pr:h=myprofilelinux --format=json")
     profile = json.loads(c.stdout)
-    assert profile["build"]["settings"] == {"os": "Windows"}
     assert profile["host"]["settings"] == {"os": "Linux"}
+
+    assert profile["build"]["settings"] == {"os": "Windows"}
+    # Check that tool_requires are properly serialized in json format
+    # https://github.com/conan-io/conan/issues/15183
+    assert profile["build"]["tool_requires"] == {'mytool/*': ["mytool/1.0"]}
diff --git a/conans/test/unittests/model/profile_test.py b/conans/test/unittests/model/profile_test.py
--- a/conans/test/unittests/model/profile_test.py
+++ b/conans/test/unittests/model/profile_test.py
@@ -127,8 +127,9 @@ def test_profile_serialize():
     profile.settings["compiler.version"] = "12"
     profile.tool_requires["*"] = ["zlib/1.2.8"]
     profile.update_package_settings({"MyPackage": [("os", "Windows")]})
-    expected_json = '{"settings": {"arch": "x86_64", "compiler": "Visual Studio", "compiler.version": "12"}, ' \
-                    '"package_settings": {"MyPackage": {"os": "Windows"}}, ' \
-                    '"options": {}, "tool_requires": {"*": ["zlib/1.2.8"]}, ' \
-                    '"conf": {"user.myfield:value": "MyVal"}, "build_env": "VAR1=1\\nVAR2=2\\n"}'
-    assert expected_json == json.dumps(profile.serialize())
+    expected_json = {
+        "settings": {"arch": "x86_64", "compiler": "Visual Studio", "compiler.version": "12"},
+        "package_settings": {"MyPackage": {"os": "Windows"}}, "options": {},
+        "tool_requires": {"*": ["'zlib/1.2.8'"]}, "conf": {"user.myfield:value": "MyVal"},
+        "build_env": "VAR1=1\nVAR2=2\n"}
+    assert expected_json == profile.serialize()

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail conans/test/unittests/model/profile_test.py::test_profile_serialize conans/test/integration/command/test_profile.py::test_profile_show_json conans/test/unittests/model/profile_test.py::ProfileTest::test_profile_settings_update conans/test/integration/command/test_profile.py::test_profile_path conans/test/unittests/model/profile_test.py::ProfileTest::test_apply conans/test/integration/command/test_profile.py::test_profile_path_missing conans/test/unittests/model/profile_test.py::ProfileTest::test_profile_dump_order conans/test/unittests/model/profile_test.py::test_update_build_requires conans/test/integration/command/test_profile.py::test_shorthand_syntax conans/test/unittests/model/profile_test.py::ProfileTest::test_package_settings_update conans/test/integration/command/test_profile.py::test_ignore_paths_when_listing_profiles conans/test/unittests/model/profile_test.py::ProfileTest::test_profile_subsettings_update
: '>>>>> End Test Output'
git checkout 2e568138707a4d35a53e063a86af2aa6ee2793fb -- conans/test/integration/command/test_profile.py conans/test/unittests/model/profile_test.py 2>/dev/null || true
