#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout aca81fcad474ee783855a40ff6a815ac5662d7db -- conans/test/unittests/tools/cmake/test_cmake_install.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/unittests/tools/cmake/test_cmake_install.py b/conans/test/unittests/tools/cmake/test_cmake_install.py
--- a/conans/test/unittests/tools/cmake/test_cmake_install.py
+++ b/conans/test/unittests/tools/cmake/test_cmake_install.py
@@ -63,3 +63,59 @@ def test_run_install_strip():
     cmake = CMake(conanfile)
     cmake.install()
     assert "--strip" in conanfile.command
+
+
+def test_run_install_cli_args():
+    """
+    Testing that the passing cli_args to install works
+    Issue related: https://github.com/conan-io/conan/issues/14235
+    """
+
+    settings = Settings.loads(get_default_settings_yml())
+    settings.os = "Linux"
+    settings.arch = "x86_64"
+    settings.build_type = "Release"
+    settings.compiler = "gcc"
+    settings.compiler.version = "11"
+
+    conanfile = ConanFileMock()
+
+    conanfile.conf = Conf()
+
+    conanfile.folders.generators = "."
+    conanfile.folders.set_base_generators(temp_folder())
+    conanfile.settings = settings
+    conanfile.folders.set_base_package(temp_folder())
+
+    write_cmake_presets(conanfile, "toolchain", "Unix Makefiles", {})
+    cmake = CMake(conanfile)
+    cmake.install(cli_args=["--prefix=/tmp"])
+    assert "--prefix=/tmp" in conanfile.command
+
+
+def test_run_install_cli_args_strip():
+    """
+    Testing that the install/strip rule is called when using cli_args
+    Issue related: https://github.com/conan-io/conan/issues/14235
+    """
+
+    settings = Settings.loads(get_default_settings_yml())
+    settings.os = "Linux"
+    settings.arch = "x86_64"
+    settings.build_type = "Release"
+    settings.compiler = "gcc"
+    settings.compiler.version = "11"
+
+    conanfile = ConanFileMock()
+
+    conanfile.conf = Conf()
+
+    conanfile.folders.generators = "."
+    conanfile.folders.set_base_generators(temp_folder())
+    conanfile.settings = settings
+    conanfile.folders.set_base_package(temp_folder())
+
+    write_cmake_presets(conanfile, "toolchain", "Unix Makefiles", {})
+    cmake = CMake(conanfile)
+    cmake.install(cli_args=["--strip"])
+    assert "--strip" in conanfile.command

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail conans/test/unittests/tools/cmake/test_cmake_install.py::test_run_install_cli_args_strip conans/test/unittests/tools/cmake/test_cmake_install.py::test_run_install_cli_args conans/test/unittests/tools/cmake/test_cmake_install.py::test_run_install_component conans/test/unittests/tools/cmake/test_cmake_install.py::test_run_install_strip
: '>>>>> End Test Output'
git checkout aca81fcad474ee783855a40ff6a815ac5662d7db -- conans/test/unittests/tools/cmake/test_cmake_install.py 2>/dev/null || true
