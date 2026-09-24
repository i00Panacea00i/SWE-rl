# 一个训练 Step 的完整解剖：从模型输出到权重同步

> **定位**：以「一个 step」为单位，把 RL 训练循环与 AGS 沙箱的每一次交互讲透——
> 兼有口头叙事的可读性与逐行代码的精度。
> **读者**：需要理解 / 复刻 / 审查训练时序的工程师，以及需要向他人讲解的汇报者。
> **配套文档**：结构坐标 [pod-training-ags-pipeline-code.md](pod-training-ags-pipeline-code.md)
> （函数索引与数据契约）；宏观闭环 [training-loop-flow.md](training-loop-flow.md)；
> 通信协议 [pod-ags-communication.md](pod-ags-communication.md)。
> **验证口径**：verl 行号来自 CFS `verl-src`（run-07 实际使用的源码副本）；
> 耗时数据来自两条真实 step 日志（step 6 与 step 11，见 §0.2）；
> 本仓库代码行号与其一致（246 行的 `swe_agent_loop.py`）。
> **数据勘误**：本文修正早期文档中"生成占 89% / 训练更新约 26s"的口径错误（根因见 §0.3）。

---

## 0. 全景：781 秒里的七幕

一个训练 step 的本质：**让一批数字分身同时在沙箱里做题，把经验收回来更新一次大脑。**

verl 主循环（`ray_trainer.py`，CFS verl-src 行号）用七个计时器把它切成七幕：

```
[1508] timing_s/step            → 发令（上一步结束，开始本步）
[1510] timing_s/gen       641s  → ① 做题（rollout）      ← ★ AGS 全程在这一幕
[1561] timing_s/reward          → ② 记分（汇总判分结果）
[1585] timing_s/old_log_prob 31s→ ③ 复算策略概率
[1621] timing_s/ref         30s → ④ 对照参考模型（KL）
[1630] timing_s/adv       0.06s → ⑤ 组内对比（GRPO 核心）
[1689] timing_s/update_actor 75s→ ⑥ 改模型（梯度更新）
[1715] timing_s/update_weights 3.4s → ⑦ 新权重灌回推理引擎
────────────────────────────────────────────────
合计 781.3 秒（step 11 稳态实测）
```

### 0.1 每个阶段的角色（一张表建立直觉）

| 幕 | 计时器 | 一句话 | 在哪里算 | 耗时占比 |
|---|---|---|---|---|
| ① 做题 | `gen` | 模型在沙箱里改代码、跑测试 | GPU 推理 + AGS 沙箱 | **82.1%** |
| ② 记分 | `reward` | 收集每条轨迹的判分结果 | 框架汇总（判分已在 ① 内完成） | ~0% |
| ③ 复算 | `old_log_prob` | 用训练引擎重算一遍 token 概率 | GPU（actor 前向） | 4.0% |
| ④ 对照 | `ref` | 冻结的基座模型给出"不训练的参照" | GPU（ref 前向） | 3.8% |
| ⑤ 对比 | `adv` | 同题多次采样互相比 | CPU（纯计算） | 0.007% |
| ⑥ 改模型 | `update_actor` | LoRA 梯度更新（26.7M 参数） | GPU（actor 反向） | 9.7% |
| ⑦ 灌权重 | `update_weights` | 新 LoRA 搬回 vLLM（51MB） | GPU↔CPU↔GPU | 0.4% |

> **口头总结**：**82% 的时间在做题，18% 的时间在学习**。
> 这是"环境采样型"强化学习的本质——模型的价值取决于它在真实世界里做得怎么样，
> 所以采样（做题）是主要成本，更新（学）是次要成本。

### 0.2 两份真实样本（全部来自 step 日志）

| 阶段 | step 6（恢复后首步）| **step 11（稳态，本文基准）** | 说明 |
|---|---|---|---|
| gen | 693.4s | **641.3s** | 做题（含沙箱执行与判分）|
| old_log_prob | 32.3s | **31.1s** | 概率复算 |
| ref | 29.4s | **29.9s** | 参考模型 |
| adv | 0.058s | **0.057s** | 组内对比 |
| update_actor | 73.5s | **75.4s** | 梯度更新 |
| update_weights | 3.47s | **3.42s** | 权重同步 |
| **合计** | 840.9s | **781.3s** | 与 `perf/time_per_step` 一致 |
| 吞吐 | 53.1 | **62.8**（token/s/卡）| 随输出长度变化 |

### 0.3 数据勘误声明（为什么本文与早期文档数字不同）

早期文档存在一处**混用错误**：把 step 11 的总时长（781.3s）与 step 6 的生成时长（693.4s）
拼在一句话里，得出"生成占 88.7%"的结论。同源核验后：

- **step 11 的正确分解**：641.3 + 31.1 + 29.9 + 0.057 + 75.4 + 3.42 = **781.29s** ✓（毫厘吻合）；
- **正确占比**：生成 **82.1%**；`update_actor` 实为 **75.4s（9.7%）**——早期"约 26s"严重低估；
- 本文所有数字以"同一日志行的自洽验算"为准（加总必须等于 `perf/time_per_step`）。

---

## 1. 第一幕 · 发令（框架组批）

**口头**：训练框架（verl）先组一个 batch——8 道题，每题采样 4 次（v1；v2 为 n=8），
得 32~64 条"待做任务"，然后交给 rollout 引擎并发执行。

**代码**（verl 侧）：

```python
1508:  with marked_timer("step", timing_raw):
1510:      with marked_timer("gen", timing_raw, color="red"):
1513:          combined_gen_output = self.async_rollout_manager.generate_sequences(combined_gen_batch)
```

`generate_sequences` 就是发令枪——它并发调用所有注册的 AgentLoop（本仓库的 `SWEAgentLoop`），
每条任务触发一次 `_episode`（`swe_agent_loop.py:43`）。

---

## 2. 第二幕 · 做题（641s，AGS 全程在场）

### 2.1 开场：为每条轨迹开一个沙箱

**口头**：框架为每条轨迹开一间"隔离考位"。这不是自动的，是我们的代码显式做的——
拿凭证 → 建沙箱 → 等就绪 → 连上 e2b → 四道自检（版本/构建/指纹/快照）→ 快照工作树
（快照是后面导出补丁的基准）。镜像已预热时约 7 秒完成。

**代码**：

```python
# verl_plugin/swe_agent_loop.py（我们的桥接层）
85:  await asyncio.to_thread(session.start)        # 建沙箱（实测中位 7.1s）
86:  record["sandbox_id"] = session.sandbox_id     # 沙箱身份证入档（可审计）
87:  record["sandbox_mode"] = session.sandbox_mode # image_override
88:  record["fingerprint"] = session.fingerprint   # 系统指纹（防跑错镜像）
```
```python
# sandbox/episode.py:124-138（模式分支：镜像覆盖为主路径）
image_tcr = getattr(self.inst, "image_tcr", "")
if image_tcr:
    instance_id = start_instance(image_tcr, tool_name="swe-ags", timeout_s=1800)
    self.sb = Sandbox.connect(instance_id, timeout=self.timeout)
```

### 2.2 命令循环：模型输出 ⇄ 沙箱执行的七步咬合（≤16 轮）

**口头**：这是整套系统的心跳——**模型写一条命令 → 沙箱执行 → 结果回填 → 模型再写**，
最多 16 轮。每一轮的代码顺序固定为七步，顺序即语义，一步都不能少。

**真实代码流程**（`swe_agent_loop.py`，行号连续）：

```python
# 第 1 步 · 模型输出：vLLM 异步生成
94:  params = dict(sampling_params)
95:  params["max_tokens"] = min(self.action_tokens, remaining)   # 受剩余预算约束
97:  generated = await self.server_manager.generate(
98:      request_id=episode_id, prompt_ids=runtime_ids,
99:      sampling_params=params, priority=priority)
101: if not generated.token_ids:                    # 空生成 → 立即失败（不静默）
102:     raise RuntimeError("Model returned no action tokens")

# 第 2 步 · token 记账：生成段并入连续序列（mask=1，参与训练）
103: merged, mask, logprobs = await self.ct_merge_assistant_token(
104:     runtime_ids, generated.token_ids, mask, ...,
106:     assistant_logprobs=generated.log_probs if generated.log_probs else None)

# 第 3 步 · 解码为动作文本
108: action = self.tokenizer.decode(generated.token_ids, skip_special_tokens=True).strip()

# 第 4 步 · 解析：提取 bash 命令 / 识别 SUBMIT
114: command, submit_requested = parse_action(action)

# 第 5 步 · AGS 执行（线程池，60 秒沙箱内超时）
116: code, out, err = await asyncio.to_thread(session.run, command, 60)

# 第 6 步 · 组装观察
117: observation = f"exit_code={code}\n{out}{err}"
118: operations += 1

# 第 7 步 · 回填与记账
138: record["steps"].append({                     # 逐轮落盘（崩溃不丢）
139:     "step": turn + 1, "kind": kind, "action": action,
140:     "executed_command": command,
141:     "observation": observation, "reward": 0.0, "done": done,
142:     "exit_code": code, "action_token_ids": generated.token_ids})
143: atomic_json(directory / "episode.json", record)
159: obs = bounded_observation(self.tokenizer, observation,   # 观察截断（768 token）
160:                            min(self.observation_tokens, available))
162: merged, new_mask, new_logprobs = await self.ct_merge_context_msg(
163:     previous_messages, messages, runtime_ids, mask, ...)  # 观察并入（mask=0）
```

### 2.3 "模型输出"的三个机制细节

1. **生成与执行是异步交错的**：`server_manager.generate` 是异步调用（vLLM 引擎），
   而沙箱执行走 `asyncio.to_thread`（线程池）——同一 worker 内多条 episode 可以在
   "A 生成时 B 执行"，这正是 32 条并行能把 641 秒填满的原因；
2. **token 账本分离"要学的"与"只看一眼的"**：
   - `ct_merge_assistant_token`（:103）把模型生成的 token 标为 **mask=1**（参与梯度）；
   - `ct_merge_context_msg`（:162）把沙箱的观察标为 **mask=0**（进上下文但不训练）。
   **这是 AGS 的执行结果进入梯度的唯一通道**；
3. **预算闸门有三道**（:90-93 / :95 / :165-166）：token 预算不足时收尾为 `token_budget`——
   v1 因此损失了 12.1% 的轨迹（v2 把预算 8192 提到 16384）。

### 2.4 "沙箱流程"的机制细节

**口头**：模型的命令不会裸奔进沙箱——`session.run` 先给它穿 5 层"防护服"：
固定目录、语法预检、超时双保险、输出截断、退出码透传。然后经 e2b 协议送到沙箱内执行。

**代码**（`episode.py:193-231`）：

```python
196: if not trusted and (not command.strip() or len(command) > 12_000 or "\x00" in command):
197:     return 2, "", "Invalid or oversized command"        # 超长直接拒绝
212: if not trusted:                                        # 第②层：语法预检
213:     syntax = (f"check=$(bash -n -c {shlex.quote(command)} 2>&1); ...")
216: wrapped = (f"cd /testbed || exit 125; {syntax}"          # 第⑤层：目录锚定
217:            f"timeout -k 5s {int(timeout)}s bash -lc {shlex.quote(inner)} 2>&1 | "  # 第③层
218:            f"/opt/miniconda3/envs/testbed/bin/python -c {shlex.quote(drain)}; "   # 第④层
219:            "codes=(\"${PIPESTATUS[@]}\"); ... exit \"${codes[0]}\"")                # 退出码透传
223: r = self.sb.commands.run(wrapped, user="root", timeout=timeout + 20)
226: self.commands.append({                                  # 命令级记账（execution.json 素材）
227:     "time": time.time(), "command": command, "exit_code": r.exit_code,
228:     "stdout": r.stdout, "stderr": r.stderr,
229:     "duration_s": round(time.monotonic() - t0, 3), "trusted": trusted})
```

**模型实际看到的世界**（`exit_code` 语义）：0 成功 · 1 测试失败（正常反馈）·
2 格式拒绝（未执行）· 124 超时 · 125 管道异常 · 127 命令不存在。

### 2.5 收尾：导出补丁 → 销毁沙箱 → 判分（第二沙箱）

**口头**：模型做完（SUBMIT 或用满 16 轮），第一个沙箱的使命结束。导出"相对初始快照的
改动"作为补丁 → 关掉并销毁沙箱 → **再开一个干净沙箱**重放补丁、跑官方测试、给分。
模型全程看不到判分过程和标准答案。

**代码**：

```python
# 导出与关闭（swe_agent_loop.py:179-184）
179: record["changed_files"] = await asyncio.to_thread(session.changed_files)  # 改动清单（互证）
181: patch = await asyncio.to_thread(session.export_patch)    # 相对快照的 git diff
183: await asyncio.to_thread(session.close)                    # sb.kill() + execution.json 落盘

# 判分（第二沙箱，episode.py:287-308）
287: session = EpisodeSession(inst, directory, timeout + 300)  # 全新沙箱
290: session.start()
292: session.sb.files.write("/tmp/candidate.patch", patch, user="root")
293: code, out, err = session.run(f"{GIT} apply --check ... && {GIT} apply ...", 60, trusted=True)
298: session.sb.files.write("/tmp/swe-eval.sh", prepare_eval_script(inst), user="root")
303: r = session.sb.commands.run(f"bash /tmp/swe-eval.sh > /tmp/swe-eval.log 2>&1", ...)
306: raw = session.sb.files.read("/tmp/swe-eval.log", user="root")   # 判分日志整份取回
```

**奖励的计算**（`harness.py:217-224`）：
```python
return round(len(g["f2p_passed"]) / len(inst.f2p), 6)      # f2p 通过比例（非 0/1 二元）
```

### 2.6 一步的 AGS 账单（口头小结）

| 口径 | 数字 |
|---|---|
| 每条 episode 的沙箱数 | **平均 2.2 个**（rollout 1 + 判分 1 + 偶发 baseline-control 0.2）|
| 每条 episode 的命令往返 | ≤16 次（v2）、实测平均 8.9 次 |
| 一步（32 条）的沙箱生命周期 | **约 70 次创建/销毁** |
| 一步的命令往返 | 约 285 次 |
| 50 步累计 | **约 3600 次沙箱生命周期** |

---

## 3. 第三幕 · 记分（reward）

**口头**：判分结果被汇总进 batch。注意时间差——**奖励在第二幕结束时就已经算好了**
（判分发生在 AgentLoop 内部），这一幕只是框架把它收进账本，本身几乎不耗时。

**代码**：

```python
# 我们的代码：奖励随 AgentLoopOutput 返回（swe_agent_loop.py:229）
reward_score=float(final["reward"]),          # f2p 通过比例（如 0.5 = 一半测试通过）

# verl 侧：[1561] marked_timer("reward")     # 汇总 batch_reward
```

> **设计要点**：奖励函数（`verl_plugin/reward.py:compute_score`）**只认 trusted 判分结果**
> （`extra_info.swe_evaluation`），缺失直接 `raise`——**没有"从模型输出文本里猜奖励"的回退路径**，
> 杜绝自评自夸。

---

## 4. 第四幕 · 复算（old_log_prob，31.1s）

**口头**：这里有个必须解释的工程细节——**做题时的概率是 vLLM 算的，训练需要的概率是
FSDP actor 算的**。两套引擎、两套数值精度（vLLM 的 kernel 与训练前向不完全一致），
所以要把刚才整条 token 序列拿回 actor 里**重新前向一遍**，得到 `old_log_prob`。
GRPO 的每次更新都以这份"复算概率"为基准——它同时是"重要性采样比"的分母。

**代码**：

```python
# verl 侧
[1585]  with marked_timer("old_log_prob", timing_raw, color="blue"):
1304:       output = self.actor_rollout_wg.compute_log_prob(batch_td)
```

---

## 5. 第五幕 · 对照（ref + KL，29.9s）

**口头**：把同一批序列喂给**参考模型**（冻结的原始基座），得到"如果没训练，模型会怎么想"。
两个概率之间的 KL 散度就是防止模型"为刷分学歪"的缰绳（v2 系数 0.0005，v1 是 0.001）。
参考模型与 actor 共享同一批 GPU（colocate + `param_offload`）。

**代码**：

```python
[1621]  ref_log_prob = self._compute_ref_log_prob(batch)
1279:       output = self.ref_policy_wg.compute_ref_log_prob(batch_td)
```

---

## 6. 第六幕 · 对比（advantage，0.06s）——GRPO 的灵魂

**口头**：0.06 秒，全场最快的舞台，却是最重要的——**同一道题的 4 次采样互相比较**：

```
组内全对  → 优势 ≈ 0 → 没东西可学（模型已会）
组内全错  → 优势 ≡ 0 → 纯浪费（模型完全不会）
有好有坏  → 学习"做得好的那次"   ← ★ 唯一产生梯度的情形
```

这就是"一道题做 4 遍"不是浪费而是必需的原因，也解释了 v1 的痛苦：
**70% 的组全错，等于 70% 的采样和沙箱开销白做**（v2 用数据筛选 + n=8 来缓解）。

**代码**：

```python
[1630]  with marked_timer("adv", timing_raw, color="brown"):
1667:       batch = compute_advantage(...)      # 组内归一化 → advantage
```

---

## 7. 第七幕 · 改模型（update_actor 75.4s → update_weights 3.4s）

### 7.1 梯度更新（update_actor，75.4s）

**口头**：用优势值加权策略梯度，反向传播。关键点——**不是更新 30B 全部参数，
只更新 26.7M 个 LoRA 参数**（约 0.088%，attention 的 q/k/v/o）。
这是 4×L20 能训 30B 的根本原因。75 秒的耗时主要花在"32 条、平均 5000 token 序列"
的 actor 前向+反向（4 卡 FSDP 分片）。

**代码**：

```python
# verl 侧
[1689]  with marked_timer("update_actor", timing_raw, color="red"):
1690:       actor_output = self._update_actor(batch)
1369:            actor_output = self.actor_rollout_wg.update_actor(batch_td)   # FSDP 反向
```

### 7.2 权重同步（update_weights，3.4s）——"改了模型，做题的人怎么知道？"

**口头**：共卡训练最微妙的一环。模型权重在 GPU 上被更新了，但下一轮做题用的是 **vLLM**——
两个引擎共享同一组 GPU，必须把新 LoRA 权重"搬"回 vLLM。搬法有三个讲究：

**讲究一 · 搬家前先让 vLLM"睡着"**：训练期间 vLLM 释放显存（`free_cache_engine=True`），
否则 44GB 单卡装不下"睡着的 vLLM + 醒着的训练"。同步时先唤醒 vLLM 的接收端。

**讲究二 · 只搬 LoRA，且逐单元搬，绝不搬全模型**：

```python
# verl 侧
[1715]  with marked_timer("update_weights", timing_raw, color="red"):
1716:       self.checkpoint_manager.update_weights(self.global_steps)
```

verl 原生用于提取 LoRA 的函数 `layered_summon_lora_params`（位于 `verl/utils/fsdp_utils.py`）
被我们的补丁**整体替换**（`deploy/patch_adapter_export.py`，作用于独立源码快照，
产出含 before/after sha256 的 `adapter-export-patch.json` 证明）：

```python
# 替换后的实现（verl_plugin/adapter_export.py）
def export_fsdp1_lora(root, max_unit_bytes=256 * 1024 * 1024):
    for prefix, unit in root.named_modules():                # 逐 FSDP 单元
        owned = [... only '.lora_A.default.' / '.lora_B.default.' ...]
        if size > max_unit_bytes:
            raise RuntimeError(f'Adapter FSDP unit exceeds gather cap: ...')
        # 逐单元：上卡 → summon_full_params(recurse=False) → 导出 → 回 CPU
        with FSDP.summon_full_params(unit, recurse=False, writeback=False, ...):
            raw[full_name] = parameter.detach().to('cpu', copy=True)
```

**——为什么必须这样？** verl 原生实现有一条"兜底路径"：分层提取失败时
`summon_full_params` 把**全模型（61GB）**搬上 GPU。在 44GB 单卡上与 vLLM 抢显存必然 OOM。
我们的补丁把这条路**改成硬报错**（`fsdp_utils.py` 内）：
```
raise RuntimeError("Empty bounded LoRA export; no full-model fallback")
```
**宁可报错重试，不许全量搬运。**

**讲究三 · 每次同步都有日志对账**（真实运行输出，每 rank 一行）：

```
BOUNDED_LORA_EXPORT {"rank": 2, "units": 384, "tensors": 384,
                     "max_unit_bytes": 262144, "adapter_bytes": 53477376}
```

解读：**384 个单元** = 48 层 × 4 模块（q/k/v/o）× A/B 两个矩阵；
**单单元上限 256KB**；**总搬运 53,477,376 字节 = 51.0MB**——正好等于最终检查点
（51.1MB）与 LoRA 参数量核算（26.7M × 2 字节）的互相印证。
**搬 51MB 而不是 61GB，这就是这一步只需 3.4 秒的原因。**

### 7.3 检查点（每 5 步）

**口头**：每 5 步把 LoRA 存一份到 CFS（`save_lora_only=True`，51MB——而不是 61GB 全量）。
这是"任何中断最多损失 1.5 小时"的保险，v1 的 CPU OOM 事故就是靠它从 step-5 零损失恢复。

**代码**：

```python
[1711]  with marked_timer("save_checkpoint", timing_raw, color="green"):
            self._save_checkpoint()     # → global_step_N/actor/{model, optim, rng, lr_scheduler}
```

---

## 8. 闭环：下一步用的是新模型

**口头**：第七幕结束，vLLM 里已经是更新后的 LoRA。下一个 step 的 641 秒做题，
就是**新策略在沙箱里的第一次实战**——做得更好 → 奖励更高 → 组内对比更明显 → 更新更有效。
这就是整个 pipeline 的闭环。

```
      ┌────────────────────────────────────────────────────────┐
      │                                                        │
      ▼                                                        │
 ①做题（641s）──► ②记分 ──► ③复算 ──► ④对照 ──► ⑤对比 ──► ⑥改模型 ──► ⑦灌权重
 AGS 沙箱 ×70            （GPU）      （GPU）   （CPU）     （GPU）     （3.4s）
                                                                    │
                                                             新 LoRA → vLLM
```

**v1 的教训与 v2 的修复**（数据来源：[rl-full-retrospective.md](../validation/rl-full-retrospective.md)）：

| 病灶 | v1 实测 | v2 修复 |
|---|---|---|
| ⑤ 对比空转 | 70% 组全错 → 优势≡0 | 数据筛选（选有信号的题）+ n 4→8 |
| ① 做题无效 | 50.6% 轨迹"只读不改" | system_prompt 行动纪律 |
| ① 提前截断 | 12.1% 轨迹撞 token 墙 | response 8192→16384 |
| ⑥ 更新抖动 | grad_norm 曾达 8.0（正常 0.02）| clip_grad=0.5 显式 |

> **一句话收尾**：一个 step 就是一次"**82% 采样、18% 学习**"的循环；
> AGS 只出现在采样里，但采样里发生的一切（每条命令、每个退出码、每次判分）
> 都通过 `AgentLoopOutput` 这一个数据结构变成梯度——**这就是整套 pipeline 的全部秘密**。

---

## 附录 A · 七幕速查表（可单独打印）

| 幕 | 计时器 | 实测（稳态） | AGS 参与 | 数据产物 |
|---|---|---|---|---|
| 发令 | `step` | — | — | — |
| ① 做题 | `gen` | 641.3s（82.1%）| ✅ 沙箱创建/≤16 轮命令/销毁/判分 | `episode.json` / `execution.json` / `candidate.patch` / `judge/*` |
| ② 记分 | `reward` | ~0s | — | — |
| ③ 复算 | `old_log_prob` | 31.1s（4.0%）| — | — |
| ④ 对照 | `ref` | 29.9s（3.8%）| — | — |
| ⑤ 对比 | `adv` | 0.057s | — | — |
| ⑥ 改模型 | `update_actor` | 75.4s（9.7%）| — | — |
| ⑦ 灌权重 | `update_weights` | 3.4s（0.4%）| — | `BOUNDED_LORA_EXPORT` 日志 |
| 检查点 | `save_checkpoint` | 每 5 步 | — | `checkpoints/global_step_N/` |
| **合计** | `step` | **781.3s** | — | — |

## 附录 B · 代码索引（两个代码库）

| 幕 | verl 侧（`ray_trainer.py`，CFS verl-src 行号）| 本仓库 |
|---|---|---|
| 发令 | 1508 / 1510 / 1513 | `swe_agent_loop.py:43`（`_episode`）|
| ① 做题 | — | `swe_agent_loop.py:85-184`；`episode.py:124-279` |
| ② 记分 | 1561 | `swe_agent_loop.py:229`；`reward.py:compute_score` |
| ③ 复算 | 1585 / 1304 | — |
| ④ 对照 | 1621 / 1279 | — |
| ⑤ 对比 | 1630 / 1667 | — |
| ⑥ 改模型 | 1689 / 1690 / 1369 | — |
| ⑦ 灌权重 | 1715 / 1716 | `verl_plugin/adapter_export.py`；`deploy/patch_adapter_export.py` |
| 检查点 | 1711 | `save_lora_only=True`（配置）|

## 附录 C · 一步内的全部落盘产物（证据链）

| 产物 | 落盘时机 | 频率 | 内容 |
|---|---|---|---|
| `episode.json` | 每轮循环后 | ≤16 次/条 | 步骤全量 + 沙箱三件套 + token 对齐 |
| `agent/execution.json` | 沙箱关闭时 | 1 次/条 | 命令级档案（stdout/exit/耗时/trusted）|
| `candidate.patch` | 补丁导出后 | 1 次/条 | 模型改动（相对初始快照）|
| `judge/result.json` | 判分完成后 | 1 次/条 | 奖励 + 逐用例状态 + `patch_sha256` |
| `judge/test.log` | 判分完成后 | 1 次/条 | 判分沙箱的完整测试输出 |
| 训练日志事件 | 实时 | 1 行/条 | `swe_episode_complete` / `swe_judge_error` |
| `BOUNDED_LORA_EXPORT` | 每次权重同步 | 4 行/步（每 rank）| 同步规模对账（384 单元 / 51MB）|
| `checkpoints/global_step_N` | 每 5 步 | — | LoRA 四件套（model/optim/rng/lr）|

---

> **维护提示**：本文数字全部可由"同一日志行加总等于 `perf/time_per_step`"验证；
> 若调整 `max_steps` / 采样数 / 预算，§0 与 §2.6 的账目需按新配置重算。
> 相关修正（连同一处数据勘误）已同步至 `pod-training-ags-pipeline-code.md` 与
> `tke-ags-tcr-pipeline-report.md`。