#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 51f3d03087414bdff763d3f45b11e37b2a28ea84 -- pandas/tests/io/excel/test_openpyxl.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/pandas/tests/io/excel/test_openpyxl.py b/pandas/tests/io/excel/test_openpyxl.py
index da94c74f2303e..53cbd1ce3cceb 100644
--- a/pandas/tests/io/excel/test_openpyxl.py
+++ b/pandas/tests/io/excel/test_openpyxl.py
@@ -13,6 +13,7 @@
     ExcelWriter,
     _OpenpyxlWriter,
 )
+from pandas.io.excel._openpyxl import OpenpyxlReader
 
 openpyxl = pytest.importorskip("openpyxl")
 
@@ -129,6 +130,31 @@ def test_engine_kwargs_append_data_only(ext, data_only, expected):
             # ExcelWriter needs us to writer something to close properly?
             DataFrame().to_excel(writer, sheet_name="Sheet2")
 
+        # ensure that data_only also works for reading
+        #  and that formulas/values roundtrip
+        assert (
+            pd.read_excel(
+                f,
+                sheet_name="Sheet1",
+                engine="openpyxl",
+                engine_kwargs={"data_only": data_only},
+            ).iloc[0, 1]
+            == expected
+        )
+
+
+@pytest.mark.parametrize("kwarg_name", ["read_only", "data_only"])
+@pytest.mark.parametrize("kwarg_value", [True, False])
+def test_engine_kwargs_append_reader(datapath, ext, kwarg_name, kwarg_value):
+    # GH 55027
+    # test that `read_only` and `data_only` can be passed to
+    #  `openpyxl.reader.excel.load_workbook` via `engine_kwargs`
+    filename = datapath("io", "data", "excel", "test1" + ext)
+    with contextlib.closing(
+        OpenpyxlReader(filename, engine_kwargs={kwarg_name: kwarg_value})
+    ) as reader:
+        assert getattr(reader.book, kwarg_name) == kwarg_value
+
 
 @pytest.mark.parametrize(
     "mode,expected", [("w", ["baz"]), ("a", ["foo", "bar", "baz"])]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_append_reader[True-read_only-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_append_reader[True-data_only-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_append_reader[False-data_only-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_append_data_only[False-=1+1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_append_reader[False-read_only-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_append_data_only[True-0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[False-dimension_missing-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_to_excel_with_openpyxl_engine[.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_empty_with_blank_row[False-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[False-dimension_small-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_if_sheet_exists_append_modes[replace-1-expected1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_append_overlay_startrow_startcol[1-1-greeting3-goodbye3-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_if_sheet_exists_append_modes[new-2-expected0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_book_and_sheets_consistent[.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[True-dimension_small-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_if_sheet_exists_raises[invalid-'"'"'invalid'"'"'' 'pandas/tests/io/excel/test_openpyxl.py::test_append_overlay_startrow_startcol[0-0-greeting0-goodbye0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_if_sheet_exists_append_modes[overlay-1-expected2-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_write[False-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_empty_trailing_rows[False-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_empty_trailing_rows[True-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_append_mode_file[.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[None-dimension_missing-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[False-dimension_large-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[True-dimension_large-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[None-dimension_large-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[False-dimension_large-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[None-dimension_small-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_multiindex_header_no_index_names[.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_write_append_mode[w-expected0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[True-dimension_small-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_workbook[True-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_ints_spelled_with_decimals[.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_empty_trailing_rows[None-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_write_cells_merge_styled[.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_append_invalid[.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_to_excel_styleconverter[.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[False-dimension_missing-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_write_append_mode[a-expected1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_if_sheet_exists_raises[None-Sheet' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[False-dimension_small-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_if_sheet_exists_raises[error-Sheet' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[None-dimension_small-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_empty_with_blank_row[None-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_append_overlay_startrow_startcol[1-0-greeting2-goodbye2-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_empty_with_blank_row[True-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[True-dimension_missing-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[None-dimension_large-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_append_overlay_startrow_startcol[0-1-greeting1-goodbye1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[True-dimension_missing-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[None-dimension_missing-0-expected_data0-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_with_bad_dimension[True-dimension_large-2-expected_data1-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_engine_kwargs_write[True-.xlsx]' 'pandas/tests/io/excel/test_openpyxl.py::test_read_workbook[False-.xlsx]'
: '>>>>> End Test Output'
git checkout 51f3d03087414bdff763d3f45b11e37b2a28ea84 -- pandas/tests/io/excel/test_openpyxl.py 2>/dev/null || true
