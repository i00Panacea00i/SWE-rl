#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 1826419f9db274ff5e64f2823d72e260527f0407 -- tests/test_root_model.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_root_model.py b/tests/test_root_model.py
--- a/tests/test_root_model.py
+++ b/tests/test_root_model.py
@@ -3,7 +3,7 @@
 import pytest
 from pydantic_core import CoreSchema
 from pydantic_core.core_schema import SerializerFunctionWrapHandler
-from typing_extensions import Annotated
+from typing_extensions import Annotated, Literal
 
 from pydantic import (
     Base64Str,
@@ -488,3 +488,43 @@ class Model(RootModel):
     assert m.root == [RModel(1), RModel(2), BModel.model_construct(value='abc')]
     assert m.model_dump() == [1, 2, {'value': 'abc'}]
     assert m.model_dump_json() == '[1,2,{"value":"abc"}]'
+
+
+@pytest.mark.parametrize(
+    'data',
+    [
+        pytest.param({'kind': 'IModel', 'int_value': 42}, id='IModel'),
+        pytest.param({'kind': 'SModel', 'str_value': 'abc'}, id='SModel'),
+    ],
+)
+def test_mixed_discriminated_union(data):
+    class IModel(BaseModel):
+        kind: Literal['IModel']
+        int_value: int
+
+    class RModel(RootModel):
+        root: IModel
+
+    class SModel(BaseModel):
+        kind: Literal['SModel']
+        str_value: str
+
+    class Model(RootModel):
+        root: Union[SModel, RModel] = Field(discriminator='kind')
+
+    assert Model(data).model_dump() == data
+    assert Model(**data).model_dump() == data
+
+
+def test_root_and_data_error():
+    class BModel(BaseModel):
+        value: int
+        other_value: str
+
+    Model = RootModel[BModel]
+
+    with pytest.raises(
+        ValueError,
+        match='"RootModel.__init__" accepts either a single positional argument or arbitrary keyword arguments',
+    ):
+        Model({'value': 42}, other_value='abc')

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail tests/test_root_model.py::test_root_and_data_error 'tests/test_root_model.py::test_mixed_discriminated_union[SModel]' 'tests/test_root_model.py::test_mixed_discriminated_union[IModel]' 'tests/test_root_model.py::test_root_model_specialized[list[int]]' tests/test_root_model.py::test_root_model_base_model_equality tests/test_root_model.py::test_construct tests/test_root_model.py::test_assignment tests/test_root_model.py::test_validate_assignment_false tests/test_root_model.py::test_validate_assignment_true tests/test_root_model.py::test_root_model_nested 'tests/test_root_model.py::test_root_model_inherited[InnerModel]' tests/test_root_model.py::test_root_model_in_root_model_default tests/test_root_model.py::test_root_model_wrong_default_value_without_validate_default tests/test_root_model.py::test_root_model_as_attr_with_validate_default tests/test_root_model.py::test_root_model_nested_equality tests/test_root_model.py::test_root_model_default_value tests/test_root_model.py::test_root_model_equality tests/test_root_model.py::test_root_model_repr tests/test_root_model.py::test_construct_nested tests/test_root_model.py::test_v1_compatibility_serializer tests/test_root_model.py::test_root_model_as_field 'tests/test_root_model.py::test_root_model_specialized[str]' tests/test_root_model.py::test_root_model_with_private_attrs_equality tests/test_root_model.py::test_model_validator_before tests/test_root_model.py::test_root_model_literal 'tests/test_root_model.py::test_root_model_inherited[list[int]]' 'tests/test_root_model.py::test_root_model_dump_with_base_model[RB]' 'tests/test_root_model.py::test_root_model_inherited[int]' tests/test_root_model.py::test_root_model_default_value_with_validate_default tests/test_root_model.py::test_private_attr tests/test_root_model.py::test_nested_root_model_naive_default tests/test_root_model.py::test_root_model_json_schema_meta 'tests/test_root_model.py::test_root_model_inherited[str]' tests/test_root_model.py::test_root_model_recursive 'tests/test_root_model.py::test_root_model_specialized[InnerModel]' tests/test_root_model.py::test_root_model_validation_error 'tests/test_root_model.py::test_root_model_specialized[int]' tests/test_root_model.py::test_root_model_default_factory tests/test_root_model.py::test_root_model_default_value_with_validate_default_on_field tests/test_root_model.py::test_model_validator_after tests/test_root_model.py::test_nested_root_model_proper_default 'tests/test_root_model.py::test_root_model_dump_with_base_model[BR]'
: '>>>>> End Test Output'
git checkout 1826419f9db274ff5e64f2823d72e260527f0407 -- tests/test_root_model.py 2>/dev/null || true
