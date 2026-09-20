#!/bin/bash
set -uxo pipefail
source /opt/miniconda3/bin/activate
conda activate testbed
cd /testbed
git config --global --add safe.directory /testbed
git config --global http.sslVerify false
git config --global user.email none@none.com
git config --global user.name SWE-Gym
git checkout 9bd651758e8ea2494837814092af70f8d9e6f7a1 -- test-data/unit/check-default-plugin.test 2>/dev/null || true
git apply -v - <<'EOF_SWEGYM'
diff --git a/test-data/unit/check-default-plugin.test b/test-data/unit/check-default-plugin.test
--- a/test-data/unit/check-default-plugin.test
+++ b/test-data/unit/check-default-plugin.test
@@ -24,6 +24,65 @@ f = g # E: Incompatible types in assignment (expression has type "Callable[[Any,
 [typing fixtures/typing-medium.pyi]
 [builtins fixtures/tuple.pyi]
 
+[case testContextManagerWithGenericFunctionAndSendType]
+from contextlib import contextmanager
+from typing import TypeVar, Generator
+
+T = TypeVar('T')
+S = TypeVar('S')
+
+@contextmanager
+def yield_id(item: T) -> Generator[T, S, None]:
+    yield item
+
+reveal_type(yield_id) # N: Revealed type is "def [T] (item: T`-1) -> contextlib.GeneratorContextManager[T`-1]"
+
+with yield_id(1) as x:
+    reveal_type(x) # N: Revealed type is "builtins.int*"
+
+f = yield_id
+def g(x, y): pass
+f = g # E: Incompatible types in assignment (expression has type "Callable[[Any, Any], Any]", variable has type "Callable[[T], GeneratorContextManager[T]]")
+[typing fixtures/typing-medium.pyi]
+[builtins fixtures/tuple.pyi]
+
+[case testAsyncContextManagerWithGenericFunction]
+# flags: --python-version 3.7
+from contextlib import asynccontextmanager
+from typing import TypeVar, AsyncIterator
+
+T = TypeVar('T')
+
+@asynccontextmanager
+async def yield_id(item: T) -> AsyncIterator[T]:
+    yield item
+
+reveal_type(yield_id) # N: Revealed type is "def [T] (item: T`-1) -> typing.AsyncContextManager[T`-1]"
+
+async with yield_id(1) as x:
+    reveal_type(x) # N: Revealed type is "builtins.int*"
+[typing fixtures/typing-async.pyi]
+[builtins fixtures/tuple.pyi]
+
+[case testAsyncContextManagerWithGenericFunctionAndSendType]
+# flags: --python-version 3.7
+from contextlib import asynccontextmanager
+from typing import TypeVar, AsyncGenerator
+
+T = TypeVar('T')
+S = TypeVar('S')
+
+@asynccontextmanager
+async def yield_id(item: T) -> AsyncGenerator[T, S]:
+    yield item
+
+reveal_type(yield_id) # N: Revealed type is "def [T] (item: T`-1) -> typing.AsyncContextManager[T`-1]"
+
+async with yield_id(1) as x:
+    reveal_type(x) # N: Revealed type is "builtins.int*"
+[typing fixtures/typing-async.pyi]
+[builtins fixtures/tuple.pyi]
+
 [case testContextManagerWithUnspecifiedArguments]
 from contextlib import contextmanager
 from typing import Callable, Iterator

EOF_SWEGYM
python -m pip install -e . --no-deps
: '>>>>> Start Test Output'
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail -p no:snail mypy/test/testcheck.py::TypeCheckSuite::testAsyncContextManagerWithGenericFunction mypy/test/testcheck.py::TypeCheckSuite::testAsyncContextManagerWithGenericFunctionAndSendType mypy/test/testcheck.py::TypeCheckSuite::testContextManagerWithGenericFunctionAndSendType mypy/test/testcheck.py::TypeCheckSuite::testContextManagerWithUnspecifiedArguments
: '>>>>> End Test Output'
git checkout 9bd651758e8ea2494837814092af70f8d9e6f7a1 -- test-data/unit/check-default-plugin.test 2>/dev/null || true
