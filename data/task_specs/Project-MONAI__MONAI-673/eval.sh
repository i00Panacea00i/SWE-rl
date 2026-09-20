#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout ef77a4be8f9890ede087c9082510acbf9b9e5fb4 -- tests/test_decathlondataset.py tests/test_mednistdataset.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_decathlondataset.py b/tests/test_decathlondataset.py
--- a/tests/test_decathlondataset.py
+++ b/tests/test_decathlondataset.py
@@ -53,6 +53,8 @@ def _test_dataset(dataset):
             root_dir=tempdir, task="Task04_Hippocampus", transform=transform, section="validation", download=False
         )
         _test_dataset(data)
+        data = DecathlonDataset(root_dir=tempdir, task="Task04_Hippocampus", section="validation", download=False)
+        self.assertTupleEqual(data[0]["image"].shape, (33, 47, 34))
         shutil.rmtree(os.path.join(tempdir, "Task04_Hippocampus"))
         try:
             data = DecathlonDataset(
diff --git a/tests/test_mednistdataset.py b/tests/test_mednistdataset.py
--- a/tests/test_mednistdataset.py
+++ b/tests/test_mednistdataset.py
@@ -43,6 +43,8 @@ def _test_dataset(dataset):
         _test_dataset(data)
         data = MedNISTDataset(root_dir=tempdir, transform=transform, section="test", download=False)
         _test_dataset(data)
+        data = MedNISTDataset(root_dir=tempdir, section="test", download=False)
+        self.assertTupleEqual(data[0]["image"].shape, (64, 64))
         shutil.rmtree(os.path.join(tempdir, "MedNIST"))
         try:
             data = MedNISTDataset(root_dir=tempdir, transform=transform, section="test", download=False)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_mednistdataset.py::TestMedNISTDataset::test_values tests/test_decathlondataset.py::TestDecathlonDataset::test_values
: '>>>>> End Test Output'
git checkout ef77a4be8f9890ede087c9082510acbf9b9e5fb4 -- tests/test_decathlondataset.py tests/test_mednistdataset.py 2>/dev/null || true
