#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 7e73134d9b73440a87d811dbb0e3d49a4352f9ce -- conans/test/integration/toolchains/cmake/test_cmaketoolchain.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/integration/toolchains/cmake/test_cmaketoolchain.py b/conans/test/integration/toolchains/cmake/test_cmaketoolchain.py
--- a/conans/test/integration/toolchains/cmake/test_cmaketoolchain.py
+++ b/conans/test/integration/toolchains/cmake/test_cmaketoolchain.py
@@ -27,19 +27,35 @@ def test_cross_build():
         arch=armv8
         build_type=Release
         """)
+    embedwin = textwrap.dedent("""
+        [settings]
+        os=Windows
+        compiler=gcc
+        compiler.version=6
+        compiler.libcxx=libstdc++11
+        arch=armv8
+        build_type=Release
+        """)
 
     client = TestClient(path_with_spaces=False)
 
     conanfile = GenConanfile().with_settings("os", "arch", "compiler", "build_type")\
         .with_generator("CMakeToolchain")
     client.save({"conanfile.py": conanfile,
-                "rpi": rpi_profile,
+                 "rpi": rpi_profile,
+                 "embedwin": embedwin,
                  "windows": windows_profile})
     client.run("install . --profile:build=windows --profile:host=rpi")
     toolchain = client.load("conan_toolchain.cmake")
 
     assert "set(CMAKE_SYSTEM_NAME Linux)" in toolchain
-    assert "set(CMAKE_SYSTEM_PROCESSOR armv8)" in toolchain
+    assert "set(CMAKE_SYSTEM_PROCESSOR aarch64)" in toolchain
+
+    client.run("install . --profile:build=windows --profile:host=embedwin")
+    toolchain = client.load("conan_toolchain.cmake")
+
+    assert "set(CMAKE_SYSTEM_NAME Windows)" in toolchain
+    assert "set(CMAKE_SYSTEM_PROCESSOR ARM64)" in toolchain
 
 
 def test_cross_build_linux_to_macos():
@@ -146,19 +162,35 @@ def test_cross_arch():
         compiler.libcxx=libstdc++11
         build_type=Release
         """)
+    profile_macos = textwrap.dedent("""
+        [settings]
+        os=Macos
+        arch=armv8
+        compiler=gcc
+        compiler.version=6
+        compiler.libcxx=libstdc++11
+        build_type=Release
+        """)
 
     client = TestClient(path_with_spaces=False)
 
     conanfile = GenConanfile().with_settings("os", "arch", "compiler", "build_type")\
         .with_generator("CMakeToolchain")
     client.save({"conanfile.py": conanfile,
-                "linux64": build_profile,
+                 "linux64": build_profile,
+                 "macos": profile_macos,
                  "linuxarm": profile_arm})
     client.run("install . --profile:build=linux64 --profile:host=linuxarm")
     toolchain = client.load("conan_toolchain.cmake")
 
     assert "set(CMAKE_SYSTEM_NAME Linux)" in toolchain
-    assert "set(CMAKE_SYSTEM_PROCESSOR armv8)" in toolchain
+    assert "set(CMAKE_SYSTEM_PROCESSOR aarch64)" in toolchain
+
+    client.run("install . --profile:build=linux64 --profile:host=macos")
+    toolchain = client.load("conan_toolchain.cmake")
+
+    assert "set(CMAKE_SYSTEM_NAME Darwin)" in toolchain
+    assert "set(CMAKE_SYSTEM_PROCESSOR arm64)" in toolchain
 
 
 def test_no_cross_build_arch():
@@ -684,6 +716,7 @@ def test_android_legacy_toolchain_flag(cmake_legacy_toolchain):
         .with_generator("CMakeToolchain")
     client.save({"conanfile.py": conanfile})
     settings = "-s arch=x86_64 -s os=Android -s os.api_level=23 -c tools.android:ndk_path=/foo"
+    expected = None
     if cmake_legacy_toolchain is not None:
         settings += f" -c tools.android:cmake_legacy_toolchain={cmake_legacy_toolchain}"
         expected = "ON" if cmake_legacy_toolchain else "OFF"

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cross_arch conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cross_build conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cross_build_conf conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_test_package_layout conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_set_linker_scripts conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_recipe_build_folders_vars conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_no_cross_build 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_user_presets_custom_location[False]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cmake_presets_singleconfig 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_presets_ninja_msvc[x86_64-x86_64]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_extra_flags_via_conf 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_user_presets_custom_location[subproject]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_android_c_library conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cmake_layout_toolchain_folder conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cross_build_user_toolchain conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_build_folder_vars_editables 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_presets_ninja_msvc[x86-x86_64]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_presets_not_found_error_msg conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cmake_presets_binary_dir_available 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_android_legacy_toolchain_flag[True]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_find_builddirs 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cmake_presets_shared_preset[CMakePresets.json]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cmake_presets_multiconfig conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_no_cross_build_arch 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_android_legacy_toolchain_flag[False]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_toolchain_cache_variables conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cross_build_linux_to_macos 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_android_legacy_toolchain_flag[None]' 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_cmake_presets_shared_preset[CMakeUserPresets.json]' 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_android_legacy_toolchain_with_compileflags[False]' 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_android_legacy_toolchain_with_compileflags[None]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_set_cmake_lang_compilers_and_launchers 'conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_android_legacy_toolchain_with_compileflags[True]' conans/test/integration/toolchains/cmake/test_cmaketoolchain.py::test_pkg_config_block
: '>>>>> End Test Output'
git checkout 7e73134d9b73440a87d811dbb0e3d49a4352f9ce -- conans/test/integration/toolchains/cmake/test_cmaketoolchain.py 2>/dev/null || true
