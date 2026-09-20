#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 438b2b7843b4b69d25c43d140b2603366a9e6453 -- tests/test_glue/test_datacatalog.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_glue/test_datacatalog.py b/tests/test_glue/test_datacatalog.py
--- a/tests/test_glue/test_datacatalog.py
+++ b/tests/test_glue/test_datacatalog.py
@@ -27,7 +27,8 @@ def test_create_database():
     response = helpers.get_database(client, database_name)
     database = response["Database"]
 
-    assert database.get("Name") == database_name
+    assert database["Name"] == database_name
+    assert database["CatalogId"] == ACCOUNT_ID
     assert database.get("Description") == database_input.get("Description")
     assert database.get("LocationUri") == database_input.get("LocationUri")
     assert database.get("Parameters") == database_input.get("Parameters")
@@ -67,14 +68,11 @@ def test_get_database_not_exits():
 
 
 @mock_glue
-def test_get_databases_empty():
+def test_get_databases():
     client = boto3.client("glue", region_name="us-east-1")
     response = client.get_databases()
     assert len(response["DatabaseList"]) == 0
 
-
-@mock_glue
-def test_get_databases_several_items():
     client = boto3.client("glue", region_name="us-east-1")
     database_name_1, database_name_2 = "firstdatabase", "seconddatabase"
 
@@ -86,7 +84,9 @@ def test_get_databases_several_items():
     )
     assert len(database_list) == 2
     assert database_list[0]["Name"] == database_name_1
+    assert database_list[0]["CatalogId"] == ACCOUNT_ID
     assert database_list[1]["Name"] == database_name_2
+    assert database_list[1]["CatalogId"] == ACCOUNT_ID
 
 
 @mock_glue
@@ -222,6 +222,7 @@ def test_get_tables():
             table["StorageDescriptor"] == table_inputs[table_name]["StorageDescriptor"]
         )
         assert table["PartitionKeys"] == table_inputs[table_name]["PartitionKeys"]
+        assert table["CatalogId"] == ACCOUNT_ID
 
 
 @mock_glue
@@ -319,6 +320,7 @@ def test_get_table_versions():
     table = client.get_table(DatabaseName=database_name, Name=table_name)["Table"]
     assert table["StorageDescriptor"]["Columns"] == []
     assert table["VersionId"] == "1"
+    assert table["CatalogId"] == ACCOUNT_ID
 
     columns = [{"Name": "country", "Type": "string"}]
     table_input = helpers.create_table_input(database_name, table_name, columns=columns)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_glue/test_datacatalog.py::test_get_databases tests/test_glue/test_datacatalog.py::test_get_tables tests/test_glue/test_datacatalog.py::test_get_table_versions tests/test_glue/test_datacatalog.py::test_delete_database tests/test_glue/test_datacatalog.py::test_create_partition_already_exist tests/test_glue/test_datacatalog.py::test_get_partitions_empty tests/test_glue/test_datacatalog.py::test_create_database tests/test_glue/test_datacatalog.py::test_batch_get_partition tests/test_glue/test_datacatalog.py::test_batch_get_partition_missing_partition tests/test_glue/test_datacatalog.py::test_update_partition_not_found_moving tests/test_glue/test_datacatalog.py::test_get_table_version_invalid_input tests/test_glue/test_datacatalog.py::test_delete_unknown_database tests/test_glue/test_datacatalog.py::test_delete_crawler tests/test_glue/test_datacatalog.py::test_get_crawler_not_exits tests/test_glue/test_datacatalog.py::test_start_crawler tests/test_glue/test_datacatalog.py::test_create_crawler_already_exists tests/test_glue/test_datacatalog.py::test_get_database_not_exits tests/test_glue/test_datacatalog.py::test_delete_partition_bad_partition tests/test_glue/test_datacatalog.py::test_batch_delete_partition tests/test_glue/test_datacatalog.py::test_create_partition tests/test_glue/test_datacatalog.py::test_stop_crawler tests/test_glue/test_datacatalog.py::test_get_table_version_not_found tests/test_glue/test_datacatalog.py::test_batch_create_partition_already_exist tests/test_glue/test_datacatalog.py::test_get_partition_not_found tests/test_glue/test_datacatalog.py::test_create_table tests/test_glue/test_datacatalog.py::test_update_partition_not_found_change_in_place tests/test_glue/test_datacatalog.py::test_get_crawlers_empty tests/test_glue/test_datacatalog.py::test_delete_table tests/test_glue/test_datacatalog.py::test_batch_update_partition tests/test_glue/test_datacatalog.py::test_get_tables_expression tests/test_glue/test_datacatalog.py::test_delete_crawler_not_exists tests/test_glue/test_datacatalog.py::test_update_partition tests/test_glue/test_datacatalog.py::test_get_crawlers_several_items tests/test_glue/test_datacatalog.py::test_batch_create_partition tests/test_glue/test_datacatalog.py::test_batch_delete_table tests/test_glue/test_datacatalog.py::test_create_crawler_scheduled tests/test_glue/test_datacatalog.py::test_update_database tests/test_glue/test_datacatalog.py::test_batch_delete_partition_with_bad_partitions tests/test_glue/test_datacatalog.py::test_get_table_when_database_not_exits tests/test_glue/test_datacatalog.py::test_delete_table_version tests/test_glue/test_datacatalog.py::test_batch_update_partition_missing_partition tests/test_glue/test_datacatalog.py::test_create_table_already_exists tests/test_glue/test_datacatalog.py::test_delete_partition tests/test_glue/test_datacatalog.py::test_get_partition tests/test_glue/test_datacatalog.py::test_stop_crawler_should_raise_exception_if_not_running tests/test_glue/test_datacatalog.py::test_update_partition_move tests/test_glue/test_datacatalog.py::test_update_unknown_database tests/test_glue/test_datacatalog.py::test_get_table_not_exits tests/test_glue/test_datacatalog.py::test_start_crawler_should_raise_exception_if_already_running tests/test_glue/test_datacatalog.py::test_create_crawler_unscheduled tests/test_glue/test_datacatalog.py::test_update_partition_cannot_overwrite tests/test_glue/test_datacatalog.py::test_create_database_already_exists
: '>>>>> End Test Output'
git checkout 438b2b7843b4b69d25c43d140b2603366a9e6453 -- tests/test_glue/test_datacatalog.py 2>/dev/null || true
