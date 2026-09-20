#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 9f91ac0eb96b1868905e1555cb819757c055b652 -- tests/test_dynamodb/models/test_key_condition_expression_parser.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_dynamodb/models/test_key_condition_expression_parser.py b/tests/test_dynamodb/models/test_key_condition_expression_parser.py
--- a/tests/test_dynamodb/models/test_key_condition_expression_parser.py
+++ b/tests/test_dynamodb/models/test_key_condition_expression_parser.py
@@ -179,6 +179,24 @@ def test_reverse_keys(self, expr):
         )
         desired_hash_key.should.equal("pk")
 
+    @pytest.mark.parametrize(
+        "expr",
+        [
+            "(job_id = :id) and start_date = :sk",
+            "job_id = :id and (start_date = :sk)",
+            "(job_id = :id) and (start_date = :sk)",
+        ],
+    )
+    def test_brackets(self, expr):
+        eav = {":id": "pk", ":sk1": "19", ":sk2": "21"}
+        desired_hash_key, comparison, range_values = parse_expression(
+            expression_attribute_values=eav,
+            key_condition_expression=expr,
+            schema=self.schema,
+            expression_attribute_names=dict(),
+        )
+        desired_hash_key.should.equal("pk")
+
 
 class TestNamesAndValues:
     schema = [{"AttributeName": "job_id", "KeyType": "HASH"}]

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_brackets[(job_id' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_brackets[job_id' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_reverse_keys[begins_with(start_date,:sk)' tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashKey::test_unknown_hash_key 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_begin_with[job_id' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_numeric_comparisons[>=]' tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashKey::test_unknown_hash_value 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_begin_with__wrong_case[Begins_with]' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_in_between[job_id' tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_unknown_hash_key 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_numeric_comparisons[' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_begin_with__wrong_case[Begins_With]' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_reverse_keys[start_date' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_unknown_range_key[job_id' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_reverse_keys[start_date=:sk' tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestNamesAndValues::test_names_and_values 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_numeric_comparisons[>]' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashKey::test_hash_key_only[job_id' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_reverse_keys[start_date>:sk' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_numeric_comparisons[=' 'tests/test_dynamodb/models/test_key_condition_expression_parser.py::TestHashAndRangeKey::test_begin_with__wrong_case[BEGINS_WITH]'
: '>>>>> End Test Output'
git checkout 9f91ac0eb96b1868905e1555cb819757c055b652 -- tests/test_dynamodb/models/test_key_condition_expression_parser.py 2>/dev/null || true
