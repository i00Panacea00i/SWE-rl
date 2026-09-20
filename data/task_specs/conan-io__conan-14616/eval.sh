#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout ea6b41b92537a563e478b66be9f5a0c13b0dd707 -- conans/test/integration/conanfile/required_conan_version_test.py conans/test/unittests/model/version/test_version_range.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/integration/conanfile/required_conan_version_test.py b/conans/test/integration/conanfile/required_conan_version_test.py
--- a/conans/test/integration/conanfile/required_conan_version_test.py
+++ b/conans/test/integration/conanfile/required_conan_version_test.py
@@ -7,139 +7,134 @@
 from conans.test.utils.tools import TestClient
 
 
-class RequiredConanVersionTest(unittest.TestCase):
-
-    def test_required_conan_version(self):
-        client = TestClient()
-        conanfile = textwrap.dedent("""
-            from conan import ConanFile
-
-            required_conan_version = ">=100.0"
-
-            class Lib(ConanFile):
-                pass
-            """)
-        client.save({"conanfile.py": conanfile})
-        client.run("export . --name=pkg --version=1.0", assert_error=True)
-        self.assertIn("Current Conan version (%s) does not satisfy the defined one (>=100.0)"
-                      % __version__, client.out)
-        client.run("source . ", assert_error=True)
-        self.assertIn("Current Conan version (%s) does not satisfy the defined one (>=100.0)"
-                      % __version__, client.out)
-        with mock.patch("conans.client.conf.required_version.client_version", "101.0"):
-            client.run("export . --name=pkg --version=1.0")
-
-        with mock.patch("conans.client.conf.required_version.client_version", "101.0-dev"):
-            client.run("export . --name=pkg --version=1.0")
-
-        client.run("install --requires=pkg/1.0@", assert_error=True)
-        self.assertIn("Current Conan version (%s) does not satisfy the defined one (>=100.0)"
-                      % __version__, client.out)
-
-    def test_required_conan_version_with_loading_issues(self):
-        # https://github.com/conan-io/conan/issues/11239
-        client = TestClient()
-        conanfile = textwrap.dedent("""
-                    from conan import missing_import
-
-                    required_conan_version = ">=100.0"
-
-                    class Lib(ConanFile):
-                        pass
-                    """)
-        client.save({"conanfile.py": conanfile})
-        client.run("export . --name=pkg --version=1.0", assert_error=True)
-        self.assertIn("Current Conan version (%s) does not satisfy the defined one (>=100.0)"
-                      % __version__, client.out)
-
-        # Assigning required_conan_version without spaces
-        conanfile = textwrap.dedent("""
-                            from conan import missing_import
-
-                            required_conan_version=">=100.0"
-
-                            class Lib(ConanFile):
-                                pass
-                            """)
-        client.save({"conanfile.py": conanfile})
-        client.run("export . --name=pkg --version=1.0", assert_error=True)
-        self.assertIn("Current Conan version (%s) does not satisfy the defined one (>=100.0)"
-                      % __version__, client.out)
-
-        # If the range is correct, everything works, of course
-        conanfile = textwrap.dedent("""
-                            from conan import ConanFile
-
-                            required_conan_version = ">1.0.0"
-
-                            class Lib(ConanFile):
-                                pass
-                            """)
-        client.save({"conanfile.py": conanfile})
+def test_required_conan_version():
+    client = TestClient()
+    conanfile = textwrap.dedent("""
+        from conan import ConanFile
+
+        required_conan_version = ">=100.0"
+
+        class Lib(ConanFile):
+            pass
+        """)
+    client.save({"conanfile.py": conanfile})
+    client.run("export . --name=pkg --version=1.0", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>=100.0)" in client.out
+    client.run("source . ", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>=100.0)" in client.out
+
+    with mock.patch("conans.client.conf.required_version.client_version", "101.0"):
         client.run("export . --name=pkg --version=1.0")
 
-    def test_comment_after_required_conan_version(self):
-        """
-        An error used to pop out if you tried to add a comment in the same line than
-        required_conan_version, as it was trying to compare against >=10.0 # This should work
-        instead of just >= 10.0
-        """
-        client = TestClient()
-        conanfile = textwrap.dedent("""
-                    from conan import ConanFile
-                    from LIB_THAT_DOES_NOT_EXIST import MADE_UP_NAME
-                    required_conan_version = ">=10.0" # This should work
-                    class Lib(ConanFile):
-                        pass
-                    """)
-        client.save({"conanfile.py": conanfile})
-        client.run("export . --name=pkg --version=1.0", assert_error=True)
-        self.assertIn("Current Conan version (%s) does not satisfy the defined one (>=10.0)"
-                      % __version__, client.out)
-
-    def test_commented_out_required_conan_version(self):
-        """
-        Used to not be able to comment out required_conan_version if we had to fall back
-        to regex check because of an error importing the recipe
-        """
-        client = TestClient()
-        conanfile = textwrap.dedent("""
-                    from conan import ConanFile
-                    from LIB_THAT_DOES_NOT_EXIST import MADE_UP_NAME
-                    required_conan_version = ">=1.0" # required_conan_version = ">=100.0"
-                    class Lib(ConanFile):
-                        pass
-                    """)
-        client.save({"conanfile.py": conanfile})
-        client.run("export . --name=pkg --version=10.0", assert_error=True)
-        self.assertNotIn("Current Conan version (%s) does not satisfy the defined one (>=1.0)"
-                      % __version__, client.out)
-
-        client = TestClient()
-        conanfile = textwrap.dedent("""
-                    from conan import ConanFile
-                    from LIB_THAT_DOES_NOT_EXIST import MADE_UP_NAME
-                    # required_conan_version = ">=10.0"
-                    class Lib(ConanFile):
-                        pass
-                    """)
-        client.save({"conanfile.py": conanfile})
-        client.run("export . --name=pkg --version=1.0", assert_error=True)
-        self.assertNotIn("Current Conan version (%s) does not satisfy the defined one (>=10.0)"
-                         % __version__, client.out)
-
-    def test_required_conan_version_invalid_syntax(self):
-        """ required_conan_version used to warn of mismatching versions if spaces were present,
-         but now we have a nicer error"""
-        # https://github.com/conan-io/conan/issues/12692
-        client = TestClient()
-        conanfile = textwrap.dedent("""
-                    from conan import ConanFile
-                    required_conan_version = ">= 1.0"
-                    class Lib(ConanFile):
-                        pass""")
-        client.save({"conanfile.py": conanfile})
-        client.run("export . --name=pkg --version=1.0", assert_error=True)
-        self.assertNotIn(f"Current Conan version ({__version__}) does not satisfy the defined one "
-                        "(>= 1.0)", client.out)
-        self.assertIn("Error parsing version range >=", client.out)
+    with mock.patch("conans.client.conf.required_version.client_version", "101.0-dev"):
+        client.run("export . --name=pkg --version=1.0")
+
+    client.run("install --requires=pkg/1.0@", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>=100.0)" in client.out
+
+
+def test_required_conan_version_with_loading_issues():
+    # https://github.com/conan-io/conan/issues/11239
+    client = TestClient()
+    conanfile = textwrap.dedent("""
+                from conan import missing_import
+
+                required_conan_version = ">=100.0"
+
+                class Lib(ConanFile):
+                    pass
+                """)
+    client.save({"conanfile.py": conanfile})
+    client.run("export . --name=pkg --version=1.0", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>=100.0)" in client.out
+
+    # Assigning required_conan_version without spaces
+    conanfile = textwrap.dedent("""
+                        from conan import missing_import
+
+                        required_conan_version=">=100.0"
+
+                        class Lib(ConanFile):
+                            pass
+                        """)
+    client.save({"conanfile.py": conanfile})
+    client.run("export . --name=pkg --version=1.0", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>=100.0)" in client.out
+
+    # If the range is correct, everything works, of course
+    conanfile = textwrap.dedent("""
+                        from conan import ConanFile
+
+                        required_conan_version = ">1.0.0"
+
+                        class Lib(ConanFile):
+                            pass
+                        """)
+    client.save({"conanfile.py": conanfile})
+    client.run("export . --name=pkg --version=1.0")
+    assert "pkg/1.0: Exported" in client.out
+
+
+def test_comment_after_required_conan_version():
+    """
+    An error used to pop out if you tried to add a comment in the same line than
+    required_conan_version, as it was trying to compare against >=10.0 # This should work
+    instead of just >= 10.0
+    """
+    client = TestClient()
+    conanfile = textwrap.dedent("""
+                from conan import ConanFile
+                from LIB_THAT_DOES_NOT_EXIST import MADE_UP_NAME
+                required_conan_version = ">=10.0" # This should work
+                class Lib(ConanFile):
+                    pass
+                """)
+    client.save({"conanfile.py": conanfile})
+    client.run("export . --name=pkg --version=1.0", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>=10.0)" in client.out
+
+
+def test_commented_out_required_conan_version():
+    """
+    Used to not be able to comment out required_conan_version if we had to fall back
+    to regex check because of an error importing the recipe
+    """
+    client = TestClient()
+    conanfile = textwrap.dedent("""
+                from conan import ConanFile
+                from LIB_THAT_DOES_NOT_EXIST import MADE_UP_NAME
+                required_conan_version = ">=1.0" # required_conan_version = ">=100.0"
+                class Lib(ConanFile):
+                    pass
+                """)
+    client.save({"conanfile.py": conanfile})
+    client.run("export . --name=pkg --version=10.0", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>=1.0)" not in client.out
+
+    client = TestClient()
+    conanfile = textwrap.dedent("""
+                from conan import ConanFile
+                from LIB_THAT_DOES_NOT_EXIST import MADE_UP_NAME
+                # required_conan_version = ">=10.0"
+                class Lib(ConanFile):
+                    pass
+                """)
+    client.save({"conanfile.py": conanfile})
+    client.run("export . --name=pkg --version=1.0", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>=10.0)" not in client.out
+
+
+def test_required_conan_version_invalid_syntax():
+    """ required_conan_version used to warn of mismatching versions if spaces were present,
+     but now we have a nicer error"""
+    # https://github.com/conan-io/conan/issues/12692
+    client = TestClient()
+    conanfile = textwrap.dedent("""
+                from conan import ConanFile
+                required_conan_version = ">= 1.0"
+                class Lib(ConanFile):
+                    pass""")
+    client.save({"conanfile.py": conanfile})
+    client.run("export . --name=pkg --version=1.0", assert_error=True)
+    assert f"Current Conan version ({__version__}) does not satisfy the defined one (>= 1.0)" not in client.out
+    assert 'Error parsing version range ">="' in client.out
diff --git a/conans/test/unittests/model/version/test_version_range.py b/conans/test/unittests/model/version/test_version_range.py
--- a/conans/test/unittests/model/version/test_version_range.py
+++ b/conans/test/unittests/model/version/test_version_range.py
@@ -87,8 +87,10 @@ def test_range_prereleases_conf(version_range, resolve_prereleases, versions_in,
     for v in versions_out:
         assert not r.contains(Version(v), resolve_prereleases), f"Expected '{version_range}' NOT to contain '{v}' (conf.ranges_resolve_prereleases={resolve_prereleases})"
 
-
-def test_wrong_range_syntax():
-    # https://github.com/conan-io/conan/issues/12692
+@pytest.mark.parametrize("version_range", [
+    ">= 1.0",  # https://github.com/conan-io/conan/issues/12692
+    ">=0.0.1 < 1.0"  # https://github.com/conan-io/conan/issues/14612
+])
+def test_wrong_range_syntax(version_range):
     with pytest.raises(ConanException):
-        VersionRange(">= 1.0")
+        VersionRange(version_range)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail conans/test/integration/conanfile/required_conan_version_test.py::test_required_conan_version_invalid_syntax 'conans/test/unittests/model/version/test_version_range.py::test_wrong_range_syntax[>=0.0.1' 'conans/test/unittests/model/version/test_version_range.py::test_range[*-conditions11-versions_in11-versions_out11]' 'conans/test/unittests/model/version/test_version_range.py::test_range[^1.2.3-conditions7-versions_in7-versions_out7]' 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[*--False-versions_in4-versions_out4]' 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[*--True-versions_in3-versions_out3]' 'conans/test/unittests/model/version/test_version_range.py::test_range[-conditions12-versions_in12-versions_out12]' 'conans/test/unittests/model/version/test_version_range.py::test_range[~1-conditions5-versions_in5-versions_out5]' 'conans/test/unittests/model/version/test_version_range.py::test_range[*--conditions17-versions_in17-versions_out17]' 'conans/test/unittests/model/version/test_version_range.py::test_range[>1' 'conans/test/unittests/model/version/test_version_range.py::test_range[^1.2-conditions6-versions_in6-versions_out6]' 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[*--None-versions_in5-versions_out5]' 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[*-True-versions_in0-versions_out0]' conans/test/integration/conanfile/required_conan_version_test.py::test_required_conan_version_with_loading_issues 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[>1' 'conans/test/unittests/model/version/test_version_range.py::test_range[~1.1.2--conditions21-versions_in21-versions_out21]' 'conans/test/unittests/model/version/test_version_range.py::test_range[=1.0.0-conditions10-versions_in10-versions_out10]' conans/test/integration/conanfile/required_conan_version_test.py::test_required_conan_version 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[*,' 'conans/test/unittests/model/version/test_version_range.py::test_range[^1.1.2--conditions20-versions_in20-versions_out20]' 'conans/test/unittests/model/version/test_version_range.py::test_range[~2.5.1-conditions4-versions_in4-versions_out4]' 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[*-False-versions_in1-versions_out1]' 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[*-None-versions_in2-versions_out2]' 'conans/test/unittests/model/version/test_version_range.py::test_range[-conditions15-versions_in15-versions_out15]' 'conans/test/unittests/model/version/test_version_range.py::test_range[*,' 'conans/test/unittests/model/version/test_version_range.py::test_range[1.0.0' 'conans/test/unittests/model/version/test_version_range.py::test_range_prereleases_conf[>1-' conans/test/integration/conanfile/required_conan_version_test.py::test_commented_out_required_conan_version conans/test/integration/conanfile/required_conan_version_test.py::test_comment_after_required_conan_version 'conans/test/unittests/model/version/test_version_range.py::test_range[^0.1.2-conditions8-versions_in8-versions_out8]' 'conans/test/unittests/model/version/test_version_range.py::test_range[<2.0-conditions1-versions_in1-versions_out1]' 'conans/test/unittests/model/version/test_version_range.py::test_wrong_range_syntax[>=' 'conans/test/unittests/model/version/test_version_range.py::test_range[>1.0.0-conditions0-versions_in0-versions_out0]' 'conans/test/unittests/model/version/test_version_range.py::test_range[~2.5-conditions3-versions_in3-versions_out3]' 'conans/test/unittests/model/version/test_version_range.py::test_range[>1-' 'conans/test/unittests/model/version/test_version_range.py::test_range[1.0.0-conditions9-versions_in9-versions_out9]'
: '>>>>> End Test Output'
git checkout ea6b41b92537a563e478b66be9f5a0c13b0dd707 -- conans/test/integration/conanfile/required_conan_version_test.py conans/test/unittests/model/version/test_version_range.py 2>/dev/null || true
