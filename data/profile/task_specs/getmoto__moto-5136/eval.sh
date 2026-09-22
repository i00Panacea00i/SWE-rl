#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 30c2aeab29c1a51805f0bed4a7c8df5b4d2f11af -- tests/test_ec2/test_subnets.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_ec2/test_subnets.py b/tests/test_ec2/test_subnets.py
--- a/tests/test_ec2/test_subnets.py
+++ b/tests/test_ec2/test_subnets.py
@@ -354,6 +354,7 @@ def test_create_subnet_response_fields():
     subnet.should.have.key("MapPublicIpOnLaunch").which.should.equal(False)
     subnet.should.have.key("OwnerId")
     subnet.should.have.key("AssignIpv6AddressOnCreation").which.should.equal(False)
+    subnet.should.have.key("Ipv6Native").which.should.equal(False)
 
     subnet_arn = "arn:aws:ec2:{region}:{owner_id}:subnet/{subnet_id}".format(
         region=subnet["AvailabilityZone"][0:-1],
@@ -390,6 +391,7 @@ def test_describe_subnet_response_fields():
     subnet.should.have.key("MapPublicIpOnLaunch").which.should.equal(False)
     subnet.should.have.key("OwnerId")
     subnet.should.have.key("AssignIpv6AddressOnCreation").which.should.equal(False)
+    subnet.should.have.key("Ipv6Native").which.should.equal(False)
 
     subnet_arn = "arn:aws:ec2:{region}:{owner_id}:subnet/{subnet_id}".format(
         region=subnet["AvailabilityZone"][0:-1],

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_ec2/test_subnets.py::test_describe_subnet_response_fields tests/test_ec2/test_subnets.py::test_create_subnet_response_fields tests/test_ec2/test_subnets.py::test_describe_subnets_dryrun tests/test_ec2/test_subnets.py::test_subnet_should_have_proper_availability_zone_set tests/test_ec2/test_subnets.py::test_available_ip_addresses_in_subnet_with_enis tests/test_ec2/test_subnets.py::test_availability_zone_in_create_subnet tests/test_ec2/test_subnets.py::test_modify_subnet_attribute_validation tests/test_ec2/test_subnets.py::test_create_subnet_with_invalid_cidr_block_parameter tests/test_ec2/test_subnets.py::test_non_default_subnet tests/test_ec2/test_subnets.py::test_create_subnet_with_invalid_cidr_range tests/test_ec2/test_subnets.py::test_subnet_create_vpc_validation tests/test_ec2/test_subnets.py::test_create_subnet_with_invalid_availability_zone tests/test_ec2/test_subnets.py::test_subnets tests/test_ec2/test_subnets.py::test_default_subnet tests/test_ec2/test_subnets.py::test_get_subnets_filtering tests/test_ec2/test_subnets.py::test_create_subnet_with_tags tests/test_ec2/test_subnets.py::test_describe_subnets_by_vpc_id tests/test_ec2/test_subnets.py::test_create_subnets_with_multiple_vpc_cidr_blocks tests/test_ec2/test_subnets.py::test_associate_subnet_cidr_block tests/test_ec2/test_subnets.py::test_run_instances_should_attach_to_default_subnet tests/test_ec2/test_subnets.py::test_disassociate_subnet_cidr_block tests/test_ec2/test_subnets.py::test_describe_subnets_by_state tests/test_ec2/test_subnets.py::test_subnet_tagging tests/test_ec2/test_subnets.py::test_subnet_get_by_id tests/test_ec2/test_subnets.py::test_available_ip_addresses_in_subnet tests/test_ec2/test_subnets.py::test_create_subnets_with_overlapping_cidr_blocks tests/test_ec2/test_subnets.py::test_create_subnet_with_invalid_cidr_range_multiple_vpc_cidr_blocks tests/test_ec2/test_subnets.py::test_modify_subnet_attribute_assign_ipv6_address_on_creation tests/test_ec2/test_subnets.py::test_modify_subnet_attribute_public_ip_on_launch
: '>>>>> End Test Output'
git checkout 30c2aeab29c1a51805f0bed4a7c8df5b4d2f11af -- tests/test_ec2/test_subnets.py 2>/dev/null || true
