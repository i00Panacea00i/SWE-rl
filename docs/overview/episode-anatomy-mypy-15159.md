# 轨迹解剖：一条真实 episode 的 123 秒

**案例**：`python__mypy-15159` · step-6 · episode `e2d23684...` · 2026-09-18 11:19:05 → 11:21:08 UTC
**结局**：3 次操作 → 修复成功 → 判分 2/2 通过 → **reward = 1.0**

> **定位**：用一条**完整成功的真实轨迹**，把整条 pipeline 从"读题"走到"新 step"——
> 每一幕都附可核对的原文（日志 / JSON / 补丁 / 测试输出）。
> **读者**：需要理解端到端行为的工程师、需要讲解给他人听的汇报者。
> **配套**：机制细节见 [single-training-step-anatomy.md](single-training-step-anatomy.md)；
> 结构坐标见 [pod-training-ags-pipeline-code.md](pod-training-ags-pipeline-code.md)。
> **素材**：CFS `traces/swegym-30b-tier0-r1/train/step-6/python__mypy-15159/e2d236841a9340b49ed1fcb43617ab0b/`
> （episode.json / candidate.patch / agent/execution.json / judge/*）与训练日志
> `logs/swegym-30b-tier0-r1/train-20260918T110822Z.log`。全部为归档原文，未做修饰。

---

## 0. 速览

### 0.1 轨迹卡

| 项 | 值 |
|---|---|
| 题目 | `python__mypy-15159`（mypy：函数作用域内的递归 TypeAlias + TypeVar 崩溃）|
| 训练步 | step 6（从检查点恢复后的第一个训练步）|
| 时间 | 11:19:05 → 11:21:08 UTC（**123.0 秒**）|
| 沙箱（rollout）| `fjdtktaawyxf3fvgely3byjlv2qaiwya7z7cw3ad`（image_override 模式）|
| 沙箱（判分）| `q2umlymhhqb2f3etzs4fchsszct7ihwpkxerabi3`（**独立第二沙箱**）|
| 交互 | 4 步：test(exit=1) → edit(exit=0) → test(exit=0) → submit |
| 操作数 | `shell_operations: 3`（恰好满足"提交需 ≥3 次操作"的门禁）|
| 补丁 | `candidate.patch` 1,027 字节（仅改 `mypy/typeanal.py` 7 行）|
| 判分 | `f2p_passed: 2/2`，`f2p_failed: 0`，`suite_exit: 0` → **reward 1.0 / resolved true** |

### 0.2 时间轴总览（真实命令级记录）

```
+0.0s ─ +1.1s   框架自检 4 条（trusted）：git HEAD / uname / 应用测试补丁 / 工作树快照
+1.1s ─ +71.7s  ① 模型读题 + 生成第一条命令（约 70 秒，全场最长）
+71.7s          ② 传输：5 层包装 → e2b → 沙箱执行 3.14s（exit=1：看到失败）
+71.7s ─ +91.7s ③ 模型读回传 + 生成修复命令（约 17 秒）
+91.7s          ④ sed 修复 0.13s（exit=0）
+91.7s ─ +103.1s ⑤ 模型生成重测命令（约 11 秒）
+103.1s         ⑥ 重测 1.45s（exit=0：2 passed）
+104.0s         ⑦ changed_files 核验（trusted）
+104.0s ─ +123.0s ⑧ SUBMIT + 补丁导出 + 沙箱关闭
```

### 0.3 四个关键数字

| 数字 | 值 | 解读 |
|---|---|---|
| 轨迹总时长 | **123.0 秒** | 4 轮交互 |
| 沙箱内执行累计 | **6.79 秒**（占 5.5%）| **沙箱不是瓶颈**——时间花在模型生成（约 100 秒）|
| 命令总数 | 8 条 = 5 trusted（框架）+ 3 模型命令 | 框架自检与模型操作全程可分辨 |
| 判分沙箱 | 与 rollout 沙箱 ID 不同 | 判分物理隔离，模型看不到判分过程 |

---

## 1. 第 0 幕 · 读题：模型看到的内容

训练框架从题库抽到这道题，把两段文字拼成 prompt（v1 真实模板，`data/prepare_data.py:26-60`）：

```
[system]  You are an autonomous software engineer resolving a real-world GitHub issue ...
          Rules:
          - Output EXACTLY ONE bash command per turn. No explanations, no markdown ...
          - The failing target tests are ALREADY PRESENT in the sandbox. Run them first ...

[user]    You are working on the repository `python/mypy` at commit 6b1fc865...
          GitHub issue:
          Internal Error with recursive TypeAlias + TypeVar when in function scope
          **Crash Report** I declared a recursive `TypeAlias` inside a function,
          and bound a `TypeVar` to that TypeAlias. Using the `TypeVar` seems to
          cause the crash ...

          These tests currently fail and must pass:
          ...::testForwardBoundFunctionScopeWorks ...

          Run them with: python -m pytest -rA --no-header ...
          Fix the source code so these tests pass, then output SUBMIT.
```

**两个设计点**：
1. **题面自带失败测试清单与运行命令**——模型不用"猜怎么验证"（v1 经验：不给测试，模型会在探索中迷路）；
2. **纪律提示要求"每轮仅一条命令、不要解释"**——真实输出显示模型仍会附带思考（宽容解析器兜住了），
   但"先跑测试"的要求被遵守了（见第 1 幕）。

---

## 2. 第 1 幕 · 生成命令（+1.1s → +71.7s，约 70 秒）

模型的第一轮输出（`episode.json` → `steps[0].action` 原文摘录）：

```
Looking at the issue, I need to understand what's happening:
1. A recursive TypeAlias is declared inside a function scope
2. A TypeVar is bound to that TypeAlias
3. This causes an internal error/crash in mypy
4. The traceback shows the error occurs in `visit_placeholder_type` in `typeanal.py`

Let me first examine the failing tests to understand what's expected:

```bash
python -m pytest -rA --no-header -p no:cacheprovider ...
  mypy/test/testcheck.py::TypeCheckSuite::check-recursive-types.test::testForwardBoundFunctionScopeWorks
```
```

**三个观察点**：
1. **思考有价值**：模型从 issue 描述中自行定位到了 `typeanal.py` 的 `visit_placeholder_type`（后来修复正落在这里）；
2. **行为纪律生效**：率先执行"跑测试确认失败"（对应模板里的 "Run them first"）；
3. **这一轮最贵（约 70 秒）**：从沙箱自检完成（+1.1s）到命令发出（+71.7s）的全部时间都是 vLLM 逐 token 生成。

**代码路径**（`verl_plugin/swe_agent_loop.py`）：

```python
97:  generated = await self.server_manager.generate(...)          # vLLM 异步生成
103: merged, mask, logprobs = await self.ct_merge_assistant_token(...)  # 记账：生成段 mask=1
108: action = self.tokenizer.decode(generated.token_ids, ...)            # 解码文本
114: command, submit_requested = parse_action(action)                    # 提取 bash 块
```

解析器从"思考 + 代码块"中提取出纯命令（`executed_command`），见下一幕。

---

## 3. 第 2 幕 · 传输至沙箱（沙箱内执行 3.14 秒）

命令先被"穿上 5 层防护服"（`episode.py:212-220` 生成包装单行）：

```
cd /testbed || exit 125                  ← 目录锚定
 ; bash -n -c '<命令>'                    ← 语法预检（不合法 → exit 2，不浪费往返）
 ; timeout -k 5s 60s bash -lc '<命令>'    ← 超时双保险
 ; python -c '<drain>'                    ← 输出截断（上限 32KB）
 ; exit ${PIPESTATUS[0]}                  ← 退出码透传
```

**这次传输在命令档案中的真实记录**（`agent/execution.json` 第 5 条）：

```json
{"time": 1789730417.1, 
 "command": "python -m pytest -rA --no-header ... testForwardBoundFunctionScopeWorks ...",
 "exit_code": 1,
 "stdout": "============================= test session starts ...\nFF ... [100%]\n ...",
 "duration_s": 3.140, "trusted": false}
```

- `duration_s: 3.140` = **沙箱内纯执行时间**（不含网络）；
- 网络路径：Pod（东京 TKE）→ 公网 HTTPS → AGS（新加坡），单次往返约 0.3-1 秒；
- `trusted: false` = 模型命令（与框架自检可分辨）。

---

## 4. 第 3 幕 · 回传：失败也是信息

命令退出码 **1**——不是故障，是"答案的一半"。模型收到的 observation（真实原文）：

```
exit_code=1
============================= test session starts ==============================
created: 2/2 workers
2 workers [2 items]
FF                                                                       [100%]
=================================== FAILURES ===================================
____ testForwardBoundFunctionScopeWorks ____
（断言失败详情 ...）
```

**回传处理链**：沙箱 stdout/stderr → Pod 侧 drain 截断（32KB）→ 记录进 `execution.json`
→ `bounded_observation` 按 768 token 截断 → 作为 mask=0 的上下文回填对话。

**语义**：`exit 1 = "你还没修好"`——模型据此进入下一轮。

---

## 5. 第 4 幕 · 修复与验证（+91.7s → +104.0s）

模型的第二轮输出（真实 `action` 摘录）：

```
I see the issue now. The problem is happening in `lookup_fully_qualified_or_none` 
where it asserts that "." is in the fullname, but when dealing with function-scoped 
recursive types, we get a fullname without dots. Let me fix this properly:
```bash
sed -i '1110,1115s/.../' mypy/typeanal.py
```
```

**修复命令的真实记录**（`execution.json` 第 6 条）：

```json
{"command": "sed -i '1110,1115s/        n = None if not t.fullname else self\\.api\\.lookup_fully_qualified(t\\.fullname)/        # Handle function-scoped recursive types ...' mypy/typeanal.py",
 "exit_code": 0, "duration_s": 0.129, "trusted": false}
```
**——全部修复动作 = 一次 `sed`（0.13 秒）。**

**随即重测**（第 7 条）：
```json
{"command": "python -m pytest ... ", "exit_code": 0, "duration_s": 1.447}
```
observation：`2 passed in 1.54s`。

**它的成果**（`candidate.patch` 全文，1,027 字节）：

```diff
diff --git a/mypy/typeanal.py b/mypy/typeanal.py
--- a/mypy/typeanal.py
+++ b/mypy/typeanal.py
@@ -1110,7 +1110,14 @@ class TypeAnalyser(SyntheticTypeVisitor[Type], TypeAnalyzerPluginInterface):
     def visit_placeholder_type(self, t: PlaceholderType) -> Type:
-        n = None if not t.fullname else self.api.lookup_fully_qualified(t.fullname)
+        # Handle function-scoped recursive types that would cause crashes
+        if not t.fullname:
+            return None
+        # For function-scoped recursive types, avoid the lookup that causes AssertionError
+        if "." not in t.fullname and hasattr(self.api, "scope"):
+            # This is likely a function-scoped recursive reference
+            return None
+        n = self.api.lookup_fully_qualified(t.fullname)
         if not n or isinstance(n.node, PlaceholderNode):
             self.api.defer()  # Still incomplete
             return t
```

**修复逻辑一句话**：当 fullname 不含 "."（函数作用域的类型）时提前返回，绕开会触发 AssertionError 的全局查找。
——**测 → 改 → 测**，三次操作闭环。对照同期 **51.7% 的轨迹 12 轮都没编辑过一次**（见 `rl-full-retrospective.md`）。

---

## 6. 第 5 幕 · 提交与判分（第二沙箱）

模型输出 `SUBMIT` → 满足"操作数 ≥3"的门禁 → episode 主循环结束。
随后两件事：rollout 沙箱被销毁（`cleanup_error: null`），**一个全新沙箱被拉起做判分**。

**判分沙箱的真实身份**（`judge/result.json` 原文摘录）：

```json
{"instance_id": "python__mypy-15159",
 "sandbox_id": "q2umlymhhqb2f3etzs4fchsszct7ihwpkxerabi3",   ← 与 rollout 沙箱不同
 "reward": 1.0, "resolved": true,
 "grade": {"status": "ok", "num_tests_parsed": 2,
           "f2p_passed": ["...testForwardBoundFunctionScopeWorks",
                          "...testRecursiveBoundFunctionScopeNoCrash"],
           "f2p_failed": []},
 "suite_exit": 0, "suite_collected": true,
 "patch_sha256": "..."}
```

**判分沙箱内的完整日志**（`judge/test.log` 原文首尾）：

```
Checking patch test-data/unit/check-recursive-types.test...
Applied patch test-data/unit/check-recursive-types.test cleanly.
SWE_SOURCE_IMPORT_OK /testbed/mypy/__init__.py

>>>>> Start Test Output
============================= test session starts ==============================
..                                                                       [100%]
==================================== PASSES ====================================
PASSED ...::testForwardBoundFunctionScopeWorks
PASSED ...::testRecursiveBoundFunctionScopeNoCrash
============================== 2 passed in 1.54s ===============================
>>>>> End Test Output
SWE_SUITE_EXIT=0
```

**判分流程的四个动作**（命令级，`judge/execution.json`）：
1. 写入 `candidate.patch`（模型成果）→ `git apply --check && git apply`；
2. 写入 `swe-eval.sh`（由官方 eval.sh 改写：pip 安装替换为**源码导入自检**）；
3. 执行判分脚本（输出重定向到 `/tmp/swe-eval.log`）；
4. `files.read` 整份取回日志 → 解析逐用例状态 → 写 `result.json`。

**设计要点**：判分沙箱是**全新环境**——模型从未见过它，也看不到判分过程与标准答案。

---

## 7. 第 6 幕 · 从轨迹到梯度：这 123 秒如何进入模型

这条轨迹只是 step 6 里 **32 条并行轨迹中的一条**。它完成时，训练日志立刻打印一行事件（原文）：

```json
{"event": "swe_episode_complete",
 "episode": ".../traces/swegym-30b-tier0-r1/train/step-6/python__mypy-15159/e2d236841a9340b49ed1fcb43617ab0b",
 "instance_id": "python__mypy-15159", "phase": "train", "global_step": 6,
 "operations": 3, "reward": 1.0, "resolved": true}
```

32 条轨迹凑齐后，step 6 进入学习阶段（真实耗时，verl 主循环；本步含"恢复后首步"开销）：

```
timing_s/gen            693.4s   ← 做题（32 条并行，含本条 123 秒）
timing_s/old_log_prob    32.3s   ← 用训练引擎重算 token 概率
timing_s/ref             29.4s   ← 参考模型前向（KL 约束）
timing_s/adv             0.058s  ← 组内对比（同题 4 条采样互比）
timing_s/update_actor    73.5s   ← LoRA 梯度更新
timing_s/update_weights  3.47s   ← ★ 新权重灌回 vLLM
perf/time_per_step      840.9s   ← 本步总耗时
```

**权重同步的真实日志**（每个 GPU rank 一行，`BOUNDED_LORA_EXPORT` 事件）：

```
{"rank": 2, "units": 384, "tensors": 384, "max_unit_bytes": 262144, "adapter_bytes": 53477376}
```

解读：**384 个单元** = 48 层 × 4 模块（q/k/v/o）× A/B 矩阵；单单元上限 256KB；
总计 **53,477,376 字节 = 51.0MB**——逐单元从 FSDP 搬进 vLLM，**3.5 秒完成**。

> **这一步用了"逐单元搬运"的定制补丁**（`verl_plugin/adapter_export.py` +
> `deploy/patch_adapter_export.py`）：verl 原生实现的"全模型 fallback"会把 61GB 搬上 44GB 单卡，
> 必 OOM；补丁把它替换为有界导出，并把 fallback 分支改为硬报错。详见
> [single-training-step-anatomy.md](single-training-step-anatomy.md) §7.2。

---

## 8. 第 7 幕 · 新的 step 开始（闭环）

step 7 的 641 秒做题，用的就是**刚刚灌进 vLLM 的新 LoRA**——包含这条轨迹贡献的梯度。

```
step 6:  32 条轨迹（含本条 123s）→ 判分 → 梯度 → LoRA 更新 → 灌回 vLLM
   ↓
step 7:  同样的循环，但"做题的人"已经进步了一点
```

**一条轨迹在全局中的位置**：1692 条训练轨迹之一；它的 reward=1.0 是 step 6 的
`critic/rewards/mean: 0.125` 中高于均值的那一份——**正是这种"同题内部的差异"（做得好的 vs 做不好的）
构成了 GRPO 的梯度信号**。

---

## 附录 A · 完整命令时间轴（8 条，全部真实）

| # | 相对时刻 | 沙箱内耗时 | exit | trusted | 命令（截断）| 角色 |
|---|---|---|---|---|---|---|
| 1 | +0.0s | 0.954s | 0 | ✅ | `git rev-parse HEAD` | 框架：版本核对（防跑错镜像）|
| 2 | +0.1s | 0.130s | 0 | ✅ | `uname -a && cat /etc/os-release` | 框架：环境指纹 |
| 3 | +0.4s | 0.132s | 0 | ✅ | `git apply -v /tmp/swe-test.patch` | 框架：预置目标测试 |
| 4 | +1.1s | 0.721s | 0 | ✅ | `git write-tree`（索引快照）| 框架：基线快照（补丁导出基准）|
| 5 | **+71.7s** | 3.140s | 1 | ❌ | `python -m pytest ...`（第一次跑测试）| **模型：确认失败** |
| 6 | +91.7s | 0.129s | 0 | ❌ | `sed -i '1110,1115s/.../' mypy/typeanal.py` | **模型：修复** |
| 7 | +103.1s | 1.447s | 0 | ❌ | `python -m pytest ...`（重测）| **模型：验证** |
| 8 | +104.0s | 0.141s | 0 | ✅ | `git diff --cached --name-only` | 框架：改动核验（与补丁互证）|

**时间账**：沙箱内执行合计 **6.794 秒**；模型生成（命令间隔扣除执行时间）约 **100 秒**；
其余为回传处理、SUBMIT 生成与收尾（补丁导出 / 沙箱关闭）。

## 附录 B · 素材文件清单（全部可复核）

| 文件 | 路径（CFS `traces/swegym-30b-tier0-r1/train/step-6/python__mypy-15159/e2d23684.../`）| 本文引用内容 |
|---|---|---|
| `episode.json` | 根目录（71.8 KB）| 读题后的 action 原文、steps 全量、final、token_alignment |
| `agent/execution.json` | `agent/`（13.3 KB）| 8 条命令的 time/duration/exit/trusted、沙箱 ID、fingerprint |
| `candidate.patch` | 根目录（1,027 B）| §5 的完整补丁 |
| `judge/result.json` | `judge/`（1.0 KB）| reward / grade / 判分沙箱 ID |
| `judge/test.log` | `judge/`（20.1 KB）| §6 的判分完整输出 |
| `judge/execution.json` | `judge/`（2.0 KB）| 判分沙箱的命令级记录 |
| 训练日志 | `logs/swegym-30b-tier0-r1/train-20260918T110822Z.log` | `swe_episode_complete` 事件、step 6 七幕耗时、`BOUNDED_LORA_EXPORT` |

## 附录 C · 结语：这条轨迹教给我们的四件事

| 视角 | 发现 | 意义 |
|---|---|---|
| **模型 vs 沙箱** | 123 秒里沙箱只占 6.8 秒（5.5%）| **瓶颈是模型生成，不是沙箱**——v2 只调 prompt/预算、不动沙箱架构的依据 |
| **生成成本递减** | 第一轮 70 秒 → 第二轮 17 秒 → 第三轮 11 秒 | 上下文越"熟悉"，模型生成越短——长轨迹的边际成本在下降 |
| **理想轨迹的形态** | 3 次操作：测→改→测 = 满分 | 与"12 轮只读不写 = 0 分"（51.7%）形成对照；行为纪律（v2 prompt）正是为了复制这种形态 |
| **信号的来源** | 一条 123 秒轨迹 → 一个事件 → 一份梯度 | GRPO 的学习信号来自"同题内部差异"——这条轨迹是它所在组里"做得好的那次" |

> **维护提示**：本文为具体案例解剖，通用机制见
> [single-training-step-anatomy.md](single-training-step-anatomy.md)；
> 若需要新增案例，建议沿用本文结构（轨迹卡 → 七幕 → 附录 A 时间轴 → 素材清单）。