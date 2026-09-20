#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 05f5bbc568b3e1b9de402d194b3e93a39b6b2c27 -- tests/test_cloudfront/test_cloudfront_distributions.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_cloudfront/test_cloudfront_distributions.py b/tests/test_cloudfront/test_cloudfront_distributions.py
--- a/tests/test_cloudfront/test_cloudfront_distributions.py
+++ b/tests/test_cloudfront/test_cloudfront_distributions.py
@@ -121,7 +121,9 @@ def test_create_distribution_s3_minimum():
 
     config.should.have.key("CacheBehaviors").equals({"Quantity": 0})
     config.should.have.key("CustomErrorResponses").equals({"Quantity": 0})
-    config.should.have.key("Comment").equals("")
+    config.should.have.key("Comment").equals(
+        "an optional comment that's not actually optional"
+    )
 
     config.should.have.key("Logging")
     logging = config["Logging"]
@@ -149,6 +151,21 @@ def test_create_distribution_s3_minimum():
     restriction.should.have.key("Quantity").equals(0)
 
 
+@mock_cloudfront
+def test_create_distribution_with_additional_fields():
+    client = boto3.client("cloudfront", region_name="us-west-1")
+
+    config = example_distribution_config("ref")
+    config["Aliases"] = {"Quantity": 2, "Items": ["alias1", "alias2"]}
+    resp = client.create_distribution(DistributionConfig=config)
+    distribution = resp["Distribution"]
+    distribution.should.have.key("DistributionConfig")
+    config = distribution["DistributionConfig"]
+    config.should.have.key("Aliases").equals(
+        {"Items": ["alias1", "alias2"], "Quantity": 2}
+    )
+
+
 @mock_cloudfront
 def test_create_distribution_returns_etag():
     client = boto3.client("cloudfront", region_name="us-east-1")

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_cloudfront/test_cloudfront_distributions.py::test_create_distribution_s3_minimum tests/test_cloudfront/test_cloudfront_distributions.py::test_create_distribution_with_additional_fields tests/test_cloudfront/test_cloudfront_distributions.py::test_delete_distribution_random_etag tests/test_cloudfront/test_cloudfront_distributions.py::test_create_distribution_with_invalid_s3_bucket tests/test_cloudfront/test_cloudfront_distributions.py::test_create_distribution_with_mismatched_originid tests/test_cloudfront/test_cloudfront_distributions.py::test_create_distribution_returns_etag tests/test_cloudfront/test_cloudfront_distributions.py::test_create_distribution_needs_unique_caller_reference tests/test_cloudfront/test_cloudfront_distributions.py::test_delete_unknown_distribution tests/test_cloudfront/test_cloudfront_distributions.py::test_get_distribution tests/test_cloudfront/test_cloudfront_distributions.py::test_delete_distribution_without_ifmatch tests/test_cloudfront/test_cloudfront_distributions.py::test_create_origin_without_origin_config tests/test_cloudfront/test_cloudfront_distributions.py::test_get_unknown_distribution tests/test_cloudfront/test_cloudfront_distributions.py::test_list_distributions_without_any tests/test_cloudfront/test_cloudfront_distributions.py::test_list_distributions
: '>>>>> End Test Output'
git checkout 05f5bbc568b3e1b9de402d194b3e93a39b6b2c27 -- tests/test_cloudfront/test_cloudfront_distributions.py 2>/dev/null || true
