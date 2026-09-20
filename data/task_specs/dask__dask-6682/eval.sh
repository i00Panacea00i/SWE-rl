#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 1d4064d0ef5794f7dc61bf3e29b5ae234d04ed4d -- dask/array/tests/test_overlap.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/dask/array/tests/test_overlap.py b/dask/array/tests/test_overlap.py
--- a/dask/array/tests/test_overlap.py
+++ b/dask/array/tests/test_overlap.py
@@ -441,6 +441,21 @@ def func(*args):
     assert all(x.compute() == size_per_slice)
 
 
+def test_map_overlap_assumes_shape_matches_first_array_if_trim_is_false():
+    # https://github.com/dask/dask/issues/6681
+    x1 = da.ones((10,), chunks=(5, 5))
+    x2 = x1.rechunk(10)
+
+    def oversum(x):
+        return x[2:-2]
+
+    z1 = da.map_overlap(oversum, x1, depth=2, trim=False)
+    assert z1.shape == (10,)
+
+    z2 = da.map_overlap(oversum, x2, depth=2, trim=False)
+    assert z2.shape == (10,)
+
+
 def test_map_overlap_deprecated_signature():
     def func(x):
         return np.array(x.sum())
@@ -461,7 +476,7 @@ def func(x):
     with pytest.warns(FutureWarning):
         y = da.map_overlap(x, func, 1, "reflect", False)
         assert y.compute() == 5
-        assert y.shape == (5,)
+        assert y.shape == (3,)
 
 
 def test_nearest_overlap():

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail dask/array/tests/test_overlap.py::test_map_overlap_assumes_shape_matches_first_array_if_trim_is_false dask/array/tests/test_overlap.py::test_map_overlap_deprecated_signature dask/array/tests/test_overlap.py::test_map_overlap_multiarray_different_depths dask/array/tests/test_overlap.py::test_constant_boundaries dask/array/tests/test_overlap.py::test_no_shared_keys_with_different_depths dask/array/tests/test_overlap.py::test_overlap_internal_asymmetric 'dask/array/tests/test_overlap.py::test_trim_boundry[periodic]' dask/array/tests/test_overlap.py::test_asymmetric_overlap_boundary_exception 'dask/array/tests/test_overlap.py::test_map_overlap_no_depth[None]' dask/array/tests/test_overlap.py::test_map_overlap_multiarray dask/array/tests/test_overlap.py::test_bad_depth_raises dask/array/tests/test_overlap.py::test_nearest dask/array/tests/test_overlap.py::test_overlap_few_dimensions dask/array/tests/test_overlap.py::test_overlap_internal_asymmetric_small 'dask/array/tests/test_overlap.py::test_map_overlap_no_depth[none]' dask/array/tests/test_overlap.py::test_map_overlap dask/array/tests/test_overlap.py::test_nearest_overlap 'dask/array/tests/test_overlap.py::test_trim_boundry[nearest]' dask/array/tests/test_overlap.py::test_reflect 'dask/array/tests/test_overlap.py::test_map_overlap_no_depth[nearest]' 'dask/array/tests/test_overlap.py::test_map_overlap_no_depth[periodic]' dask/array/tests/test_overlap.py::test_map_overlap_multiarray_block_broadcast dask/array/tests/test_overlap.py::test_depth_equals_boundary_length dask/array/tests/test_overlap.py::test_constant dask/array/tests/test_overlap.py::test_periodic dask/array/tests/test_overlap.py::test_trim_internal dask/array/tests/test_overlap.py::test_none_boundaries dask/array/tests/test_overlap.py::test_some_0_depth 'dask/array/tests/test_overlap.py::test_trim_boundry[none]' dask/array/tests/test_overlap.py::test_fractional_slice dask/array/tests/test_overlap.py::test_0_depth dask/array/tests/test_overlap.py::test_map_overlap_multiarray_defaults 'dask/array/tests/test_overlap.py::test_map_overlap_no_depth[0]' dask/array/tests/test_overlap.py::test_map_overlap_multiarray_variadic dask/array/tests/test_overlap.py::test_one_chunk_along_axis dask/array/tests/test_overlap.py::test_overlap_small dask/array/tests/test_overlap.py::test_boundaries dask/array/tests/test_overlap.py::test_overlap_few_dimensions_small dask/array/tests/test_overlap.py::test_map_overlap_multiarray_uneven_numblocks_exception 'dask/array/tests/test_overlap.py::test_map_overlap_no_depth[reflect]' dask/array/tests/test_overlap.py::test_overlap_internal 'dask/array/tests/test_overlap.py::test_trim_boundry[reflect]' dask/array/tests/test_overlap.py::test_overlap
: '>>>>> End Test Output'
git checkout 1d4064d0ef5794f7dc61bf3e29b5ae234d04ed4d -- dask/array/tests/test_overlap.py 2>/dev/null || true
