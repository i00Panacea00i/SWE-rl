#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 8ee553aae909a88df483d6454ed9af58c494879f -- tests/test_model_validator.py 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/tests/test_model_validator.py b/tests/test_model_validator.py
--- a/tests/test_model_validator.py
+++ b/tests/test_model_validator.py
@@ -2,6 +2,8 @@
 
 from typing import Any, Dict, cast
 
+import pytest
+
 from pydantic import BaseModel, ValidationInfo
 from pydantic.decorators import ModelWrapValidatorHandler, model_validator
 
@@ -29,13 +31,14 @@ def val_model(cls, values: Any, handler: ModelWrapValidatorHandler[Model], info:
     assert Model.model_validate(Model(x=1, y=2)).model_dump() == {'x': 3, 'y': 4}
 
 
-def test_model_validator_before() -> None:
+@pytest.mark.parametrize('classmethod_decorator', [classmethod, lambda x: x])
+def test_model_validator_before(classmethod_decorator: Any) -> None:
     class Model(BaseModel):
         x: int
         y: int
 
         @model_validator(mode='before')
-        @classmethod
+        @classmethod_decorator
         def val_model(cls, values: Any, info: ValidationInfo) -> dict[str, Any] | Model:
             assert not info.context
             if isinstance(values, dict):
@@ -66,3 +69,17 @@ def val_model(self, info: ValidationInfo) -> Model:
 
     assert Model(x=1, y=2).model_dump() == {'x': 2, 'y': 3}
     assert Model.model_validate(Model(x=1, y=2)).model_dump() == {'x': 3, 'y': 4}
+
+
+def test_subclass() -> None:
+    class Human(BaseModel):
+        @model_validator(mode='before')
+        @classmethod
+        def run_model_validator(cls, values: dict[str, Any]) -> dict[str, Any]:
+            values['age'] *= 2
+            return values
+
+    class Person(Human):
+        age: int
+
+    assert Person(age=28).age == 56

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail 'tests/test_model_validator.py::test_model_validator_before[<lambda>]' tests/test_model_validator.py::test_subclass tests/test_model_validator.py::test_model_validator_after tests/test_model_validator.py::test_model_validator_wrap 'tests/test_model_validator.py::test_model_validator_before[classmethod]'
: '>>>>> End Test Output'
git checkout 8ee553aae909a88df483d6454ed9af58c494879f -- tests/test_model_validator.py 2>/dev/null || true
