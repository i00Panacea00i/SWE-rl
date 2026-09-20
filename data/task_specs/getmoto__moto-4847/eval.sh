#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout de559e450dd921bf7f85b0750001a6cb4f840758 -- tests/terraform-tests.success.txt tests/test_acm/test_acm.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/terraform-tests.success.txt b/tests/terraform-tests.success.txt
--- a/tests/terraform-tests.success.txt
+++ b/tests/terraform-tests.success.txt
@@ -1,4 +1,5 @@
 TestAccAWSAccessKey
+TestAccAWSAcmCertificateDataSource
 TestAccAWSAPIGatewayV2Authorizer
 TestAccAWSAPIGatewayV2IntegrationResponse
 TestAccAWSAPIGatewayV2Model
diff --git a/tests/test_acm/test_acm.py b/tests/test_acm/test_acm.py
--- a/tests/test_acm/test_acm.py
+++ b/tests/test_acm/test_acm.py
@@ -164,6 +164,13 @@ def test_describe_certificate():
     resp["Certificate"]["KeyAlgorithm"].should.equal("RSA_2048")
     resp["Certificate"]["Status"].should.equal("ISSUED")
     resp["Certificate"]["Type"].should.equal("IMPORTED")
+    resp["Certificate"].should.have.key("RenewalEligibility").equals("INELIGIBLE")
+    resp["Certificate"].should.have.key("Options")
+    resp["Certificate"].should.have.key("DomainValidationOptions").length_of(1)
+
+    validation_option = resp["Certificate"]["DomainValidationOptions"][0]
+    validation_option.should.have.key("DomainName").equals(SERVER_COMMON_NAME)
+    validation_option.shouldnt.have.key("ValidationDomain")
 
 
 @mock_acm
@@ -524,6 +531,14 @@ def test_request_certificate_no_san():
     resp2 = client.describe_certificate(CertificateArn=resp["CertificateArn"])
     resp2.should.contain("Certificate")
 
+    resp2["Certificate"].should.have.key("RenewalEligibility").equals("INELIGIBLE")
+    resp2["Certificate"].should.have.key("Options")
+    resp2["Certificate"].should.have.key("DomainValidationOptions").length_of(1)
+
+    validation_option = resp2["Certificate"]["DomainValidationOptions"][0]
+    validation_option.should.have.key("DomainName").equals("google.com")
+    validation_option.should.have.key("ValidationDomain").equals("google.com")
+
 
 # Also tests the SAN code
 @mock_acm

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_acm/test_acm.py::test_request_certificate_no_san tests/test_acm/test_acm.py::test_describe_certificate tests/test_acm/test_acm.py::test_import_certificate_with_tags tests/test_acm/test_acm.py::test_resend_validation_email_invalid tests/test_acm/test_acm.py::test_remove_tags_from_invalid_certificate tests/test_acm/test_acm.py::test_import_certificate tests/test_acm/test_acm.py::test_request_certificate tests/test_acm/test_acm.py::test_list_certificates_by_status tests/test_acm/test_acm.py::test_request_certificate_issued_status tests/test_acm/test_acm.py::test_export_certificate tests/test_acm/test_acm.py::test_request_certificate_with_mutiple_times tests/test_acm/test_acm.py::test_remove_tags_from_certificate tests/test_acm/test_acm.py::test_resend_validation_email tests/test_acm/test_acm.py::test_import_bad_certificate tests/test_acm/test_acm.py::test_describe_certificate_with_bad_arn tests/test_acm/test_acm.py::test_request_certificate_issued_status_with_wait_in_envvar tests/test_acm/test_acm.py::test_delete_certificate tests/test_acm/test_acm.py::test_add_tags_to_invalid_certificate tests/test_acm/test_acm.py::test_list_tags_for_invalid_certificate tests/test_acm/test_acm.py::test_request_certificate_with_tags tests/test_acm/test_acm.py::test_elb_acm_in_use_by tests/test_acm/test_acm.py::test_operations_with_invalid_tags tests/test_acm/test_acm.py::test_add_tags_to_certificate tests/test_acm/test_acm.py::test_get_invalid_certificate tests/test_acm/test_acm.py::test_add_too_many_tags tests/test_acm/test_acm.py::test_list_certificates tests/test_acm/test_acm.py::test_export_certificate_with_bad_arn
: '>>>>> End Test Output'
git checkout de559e450dd921bf7f85b0750001a6cb4f840758 -- tests/terraform-tests.success.txt tests/test_acm/test_acm.py 2>/dev/null || true
