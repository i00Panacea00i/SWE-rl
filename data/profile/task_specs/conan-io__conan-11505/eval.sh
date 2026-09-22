#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout b7a81982e17ebcae93fbd22730e619d775c8e72c -- conans/test/integration/toolchains/microsoft/test_msbuilddeps.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/conans/test/integration/toolchains/microsoft/test_msbuilddeps.py b/conans/test/integration/toolchains/microsoft/test_msbuilddeps.py
new file mode 100644
--- /dev/null
+++ b/conans/test/integration/toolchains/microsoft/test_msbuilddeps.py
@@ -0,0 +1,23 @@
+import os
+
+import pytest
+
+from conans.test.utils.tools import TestClient
+
+
+@pytest.mark.parametrize(
+    "arch,exp_platform",
+    [
+        ("x86", "Win32"),
+        ("x86_64", "x64"),
+        ("armv7", "ARM"),
+        ("armv8", "ARM64"),
+    ],
+)
+def test_msbuilddeps_maps_architecture_to_platform(arch, exp_platform):
+    client = TestClient(path_with_spaces=False)
+    client.run("new hello/0.1 --template=msbuild_lib")
+    client.run(f"install . -g MSBuildDeps -s arch={arch} -pr:b=default -if=install")
+    toolchain = client.load(os.path.join("conan", "conantoolchain.props"))
+    expected_import = f"""<Import Condition="'$(Configuration)' == 'Release' And '$(Platform)' == '{exp_platform}'" Project="conantoolchain_release_{exp_platform.lower()}.props"/>"""
+    assert expected_import in toolchain

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'conans/test/integration/toolchains/microsoft/test_msbuilddeps.py::test_msbuilddeps_maps_architecture_to_platform[armv8-ARM64]' 'conans/test/integration/toolchains/microsoft/test_msbuilddeps.py::test_msbuilddeps_maps_architecture_to_platform[armv7-ARM]' 'conans/test/integration/toolchains/microsoft/test_msbuilddeps.py::test_msbuilddeps_maps_architecture_to_platform[x86-Win32]' 'conans/test/integration/toolchains/microsoft/test_msbuilddeps.py::test_msbuilddeps_maps_architecture_to_platform[x86_64-x64]'
: '>>>>> End Test Output'
git checkout b7a81982e17ebcae93fbd22730e619d775c8e72c -- conans/test/integration/toolchains/microsoft/test_msbuilddeps.py 2>/dev/null || true
