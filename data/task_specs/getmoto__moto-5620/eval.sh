#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 80db33cb44c77331b3b53bc7cba2caf56e61c5fb -- tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py b/tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py
--- a/tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py
+++ b/tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py
@@ -798,3 +798,75 @@ def test_transact_write_items_multiple_operations_fail():
         err["Message"]
         == "TransactItems can only contain one of Check, Put, Update or Delete"
     )
+
+
+@mock_dynamodb
+def test_update_primary_key_with_sortkey():
+    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
+    schema = {
+        "KeySchema": [
+            {"AttributeName": "pk", "KeyType": "HASH"},
+            {"AttributeName": "sk", "KeyType": "RANGE"},
+        ],
+        "AttributeDefinitions": [
+            {"AttributeName": "pk", "AttributeType": "S"},
+            {"AttributeName": "sk", "AttributeType": "S"},
+        ],
+    }
+    dynamodb.create_table(
+        TableName="test-table", BillingMode="PAY_PER_REQUEST", **schema
+    )
+
+    table = dynamodb.Table("test-table")
+    base_item = {"pk": "testchangepk", "sk": "else"}
+    table.put_item(Item=base_item)
+
+    with pytest.raises(ClientError) as exc:
+        table.update_item(
+            Key={"pk": "n/a", "sk": "else"},
+            UpdateExpression="SET #attr1 = :val1",
+            ExpressionAttributeNames={"#attr1": "pk"},
+            ExpressionAttributeValues={":val1": "different"},
+        )
+    err = exc.value.response["Error"]
+    err["Code"].should.equal("ValidationException")
+    err["Message"].should.equal(
+        "One or more parameter values were invalid: Cannot update attribute pk. This attribute is part of the key"
+    )
+
+    table.get_item(Key={"pk": "testchangepk", "sk": "else"})["Item"].should.equal(
+        {"pk": "testchangepk", "sk": "else"}
+    )
+
+
+@mock_dynamodb
+def test_update_primary_key():
+    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
+    schema = {
+        "KeySchema": [{"AttributeName": "pk", "KeyType": "HASH"}],
+        "AttributeDefinitions": [{"AttributeName": "pk", "AttributeType": "S"}],
+    }
+    dynamodb.create_table(
+        TableName="without_sk", BillingMode="PAY_PER_REQUEST", **schema
+    )
+
+    table = dynamodb.Table("without_sk")
+    base_item = {"pk": "testchangepk"}
+    table.put_item(Item=base_item)
+
+    with pytest.raises(ClientError) as exc:
+        table.update_item(
+            Key={"pk": "n/a"},
+            UpdateExpression="SET #attr1 = :val1",
+            ExpressionAttributeNames={"#attr1": "pk"},
+            ExpressionAttributeValues={":val1": "different"},
+        )
+    err = exc.value.response["Error"]
+    err["Code"].should.equal("ValidationException")
+    err["Message"].should.equal(
+        "One or more parameter values were invalid: Cannot update attribute pk. This attribute is part of the key"
+    )
+
+    table.get_item(Key={"pk": "testchangepk"})["Item"].should.equal(
+        {"pk": "testchangepk"}
+    )

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_update_primary_key tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_update_primary_key_with_sortkey tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_query_gsi_with_wrong_key_attribute_names_throws_exception tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_update_expression_with_trailing_comma 'tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_hash_key_can_only_use_equals_operations[<]' tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_creating_table_with_0_global_indexes tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_empty_expressionattributenames_with_empty_projection tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_create_table_with_missing_attributes 'tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_hash_key_can_only_use_equals_operations[<=]' tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_batch_put_item_with_empty_value tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_batch_get_item_non_existing_table 'tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_hash_key_can_only_use_equals_operations[>=]' tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_empty_expressionattributenames tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_create_table_with_redundant_and_missing_attributes tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_put_item_wrong_datatype tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_query_begins_with_without_brackets tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_put_item_wrong_attribute_type tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_hash_key_cannot_use_begins_with_operations tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_transact_write_items_multiple_operations_fail tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_update_item_range_key_set tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_multiple_transactions_on_same_item tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_batch_write_item_non_existing_table tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_query_table_with_wrong_key_attribute_names_throws_exception 'tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_update_item_with_duplicate_expressions[set' tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_create_table_with_redundant_attributes tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_update_item_non_existent_table 'tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_hash_key_can_only_use_equals_operations[>]' tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_put_item_empty_set tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_empty_expressionattributenames_with_projection tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_creating_table_with_0_local_indexes tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py::test_transact_write_items__too_many_transactions
: '>>>>> End Test Output'
git checkout 80db33cb44c77331b3b53bc7cba2caf56e61c5fb -- tests/test_dynamodb/exceptions/test_dynamodb_exceptions.py 2>/dev/null || true
