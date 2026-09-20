#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 7b054f1d8f4a2343268f5182d47996a5469b10dc -- dask/bag/tests/test_random.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/dask/bag/tests/test_random.py b/dask/bag/tests/test_random.py
--- a/dask/bag/tests/test_random.py
+++ b/dask/bag/tests/test_random.py
@@ -51,6 +51,27 @@ def test_choices_k_equal_bag_size_with_unbalanced_partitions():
     assert all(i in seq for i in li)
 
 
+def test_choices_with_more_bag_partitons():
+    # test with npartitions > split_every
+    seq = range(100)
+    sut = db.from_sequence(seq, npartitions=10)
+    li = list(random.choices(sut, k=10, split_every=8).compute())
+    assert sut.map_partitions(len).compute() == (10, 10, 10, 10, 10, 10, 10, 10, 10, 10)
+    assert len(li) == 10
+    assert all(i in seq for i in li)
+
+
+def test_sample_with_more_bag_partitons():
+    # test with npartitions > split_every
+    seq = range(100)
+    sut = db.from_sequence(seq, npartitions=10)
+    li = list(random.sample(sut, k=10, split_every=8).compute())
+    assert sut.map_partitions(len).compute() == (10, 10, 10, 10, 10, 10, 10, 10, 10, 10)
+    assert len(li) == 10
+    assert all(i in seq for i in li)
+    assert len(set(li)) == len(li)
+
+
 def test_sample_size_exactly_k():
     seq = range(20)
     sut = db.from_sequence(seq, npartitions=3)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail dask/bag/tests/test_random.py::test_choices_with_more_bag_partitons dask/bag/tests/test_random.py::test_sample_with_more_bag_partitons dask/bag/tests/test_random.py::test_choices_empty_partition dask/bag/tests/test_random.py::test_sample_size_exactly_k dask/bag/tests/test_random.py::test_choices_size_exactly_k dask/bag/tests/test_random.py::test_sample_k_bigger_than_bag_size dask/bag/tests/test_random.py::test_sample_empty_partition dask/bag/tests/test_random.py::test_choices_k_equal_bag_size_with_unbalanced_partitions dask/bag/tests/test_random.py::test_sample_size_k_bigger_than_smallest_partition_size dask/bag/tests/test_random.py::test_choices_k_bigger_than_smallest_partition_size dask/bag/tests/test_random.py::test_partitions_are_coerced_to_lists dask/bag/tests/test_random.py::test_reservoir_sample_map_partitions_correctness dask/bag/tests/test_random.py::test_sample_k_equal_bag_size_with_unbalanced_partitions dask/bag/tests/test_random.py::test_weighted_sampling_without_replacement dask/bag/tests/test_random.py::test_reservoir_sample_with_replacement_map_partitions_correctness dask/bag/tests/test_random.py::test_choices_k_bigger_than_bag_size dask/bag/tests/test_random.py::test_sample_return_bag
: '>>>>> End Test Output'
git checkout 7b054f1d8f4a2343268f5182d47996a5469b10dc -- dask/bag/tests/test_random.py 2>/dev/null || true
