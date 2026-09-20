#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 5c8afe65a69d9fb127c32fbf288156d7c13da346 -- tests/test_create_model.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_create_model.py b/tests/test_create_model.py
--- a/tests/test_create_model.py
+++ b/tests/test_create_model.py
@@ -3,6 +3,7 @@
 from typing import Generic, Optional, Tuple, TypeVar
 
 import pytest
+from typing_extensions import Annotated
 
 from pydantic import (
     BaseModel,
@@ -516,6 +517,34 @@ def test_create_model_non_annotated():
         create_model('FooModel', foo=(str, ...), bar=123)
 
 
+@pytest.mark.parametrize(
+    'annotation_type,field_info',
+    [
+        (bool, Field(alias='foo_bool_alias', description='foo boolean')),
+        (str, Field(alias='foo_str_alis', description='foo string')),
+    ],
+)
+def test_create_model_typing_annotated_field_info(annotation_type, field_info):
+    annotated_foo = Annotated[annotation_type, field_info]
+    model = create_model('FooModel', foo=annotated_foo, bar=(int, 123))
+
+    assert model.model_fields.keys() == {'foo', 'bar'}
+
+    foo = model.model_fields.get('foo')
+
+    assert foo is not None
+    assert foo.annotation == annotation_type
+    assert foo.alias == field_info.alias
+    assert foo.description == field_info.description
+
+
+def test_create_model_expect_field_info_as_metadata_typing():
+    annotated_foo = Annotated[int, 10]
+
+    with pytest.raises(PydanticUserError, match=r'Field definitions should be a Annotated\[<type>, <FieldInfo>\]'):
+        create_model('FooModel', foo=annotated_foo)
+
+
 def test_create_model_tuple():
     model = create_model('FooModel', foo=(Tuple[int, int], (1, 2)))
     assert model().foo == (1, 2)

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/test_create_model.py::test_create_model_typing_annotated_field_info[bool-field_info0]' tests/test_create_model.py::test_create_model_expect_field_info_as_metadata_typing 'tests/test_create_model.py::test_create_model_typing_annotated_field_info[str-field_info1]' tests/test_create_model.py::test_private_attr_set_name_do_not_crash_if_not_callable tests/test_create_model.py::test_create_model_protected_namespace_default tests/test_create_model.py::test_del_model_attr_error tests/test_create_model.py::test_resolving_forward_refs_across_modules tests/test_create_model.py::test_del_model_attr_with_privat_attrs tests/test_create_model.py::test_config_and_base tests/test_create_model.py::test_create_model_pickle tests/test_create_model.py::test_inheritance tests/test_create_model.py::test_create_model_field_and_model_title tests/test_create_model.py::test_repeat_base_usage tests/test_create_model.py::test_json_schema_with_inner_models_with_duplicate_names tests/test_create_model.py::test_create_model_must_not_reset_parent_namespace tests/test_create_model.py::test_create_model_usage tests/test_create_model.py::test_del_model_attr tests/test_create_model.py::test_create_model_multi_inheritance tests/test_create_model.py::test_private_attr_set_name tests/test_create_model.py::test_create_model_with_doc tests/test_create_model.py::test_del_model_attr_with_privat_attrs_twice_error tests/test_create_model.py::test_inheritance_validators tests/test_create_model.py::test_create_model_tuple_3 tests/test_create_model.py::test_del_model_attr_with_privat_attrs_error tests/test_create_model.py::test_type_field_in_the_same_module tests/test_create_model.py::test_dynamic_and_static 'tests/test_create_model.py::test_private_descriptors[True-object]' tests/test_create_model.py::test_create_model_custom_protected_namespace tests/test_create_model.py::test_create_model_with_slots tests/test_create_model.py::test_inheritance_validators_always tests/test_create_model.py::test_private_attr_default_descriptor_attribute_error tests/test_create_model.py::test_create_model tests/test_create_model.py::test_create_model_multiple_protected_namespace 'tests/test_create_model.py::test_private_descriptors[False-ModelPrivateAttr]' tests/test_create_model.py::test_create_model_tuple 'tests/test_create_model.py::test_private_descriptors[True-ModelPrivateAttr]' tests/test_create_model.py::test_create_model_field_description tests/test_create_model.py::test_custom_config tests/test_create_model.py::test_inheritance_validators_all 'tests/test_create_model.py::test_private_descriptors[False-object]' tests/test_create_model.py::test_field_wrong_tuple tests/test_create_model.py::test_custom_config_extras tests/test_create_model.py::test_create_model_protected_namespace_real_conflict tests/test_create_model.py::test_invalid_name tests/test_create_model.py::test_custom_config_inherits tests/test_create_model.py::test_funky_name tests/test_create_model.py::test_create_model_non_annotated
: '>>>>> End Test Output'
git checkout 5c8afe65a69d9fb127c32fbf288156d7c13da346 -- tests/test_create_model.py 2>/dev/null || true
