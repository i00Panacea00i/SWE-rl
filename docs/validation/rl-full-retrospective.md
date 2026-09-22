# 强化学习训练全量复盘：reward=0 归因与下一轮配置方案

> **复盘对象**：run-07 `swegym-30b-tier0-r1`（Qwen3-Coder-30B-A3B + LoRA r=32, GRPO, 50 步, L20×4）
> **数据基础**：1692 条训练轨迹全量分类 + 422 个 GRPO 组分析 + 45 步训练指标快照 + 400 条 pass@4 评估
> **日期**：2026-09-22

---

## 0. 摘要（TL;DR）

**核心结论：reward=0 的主导原因不是"模型不会解题"，而是行为层缺陷**——
51.7% 的零奖励轨迹**从未产生任何编辑**（只读瘫痪），29.2% 是"改了但方向错"。
两者相加 80.9% 的失败发生在"动手能力"层面，而非"解题知识"层面。

**三个量化支柱**：

1. **70% 的 GRPO 组 advantage ≡ 0**（297/422 全零组）——每 10 步训练有 7 步的梯度为零；
2. **训练确实改善了行为**（格式错误 ↓88%、编辑 ↑21%、测试 ↑30%），**但未转化为解题率**
   （通过率 6.9% → 13.0% 峰值 → 8.9% 回落）；
3. **梯度爆炸事故**：step 41/44/45 的 `grad_norm` 达 5.9-8.0（正常值 0.02 的 **300 倍**），
   全部发生在全零奖励步，且**紧随其后通过率从峰值回落 31%**——这是策略被破坏的直接证据。

**下一轮核心动作**（完整清单见 §5）：
数据画像筛选（20 → 40-60 题）+ 开组过滤（`filter_groups`）+ response 预算 8192 → 16384 +
prompt 行动纪律 + 梯度裁剪收紧 + n=4 → 8。

---

## 1. 复盘范围与方法

| 维度 | 数据 | 方法 |
|---|---|---|
| 轨迹级 | 1692 条（50 步 × 8 题 × 4 采样 + step-1 重跑批次） | 症状簇互斥归类（8 类） |
| 组级 | 422 组（step × 题） | GRPO advantage 零组判定 |
| 步级 | 45 步指标（step 6-50） | reward/entropy/kl/grad_norm/clip 趋势 |
| 评估级 | 400 条 pass@4（40 题 × 4 采样 × 2 模型） | pass@1/pass@4/f2p 对照 |
| 代码级 | `configs/grpo_4l20_30b.sh`、`configs/swe_agent.yaml`、`verl_plugin/swe_agent_loop.py`、`sandbox/action_protocol.py` | 参数与行为协议审查 |

---

## 2. 训练实际结果回顾

### 2.1 reward 分布（轨迹级，n=1692）

| reward | 条数 | 占比 | 含义 |
|---|---|---|---|
| **0.0** | **1480** | **87.5%** | 零奖励（F2P 全失败） |
| 0.2 | 1 | 0.1% | 1 项部分通过 |
| 0.333 | 11 | 0.7% | f2p 部分通过 |
| 0.5 | 22 | 1.3% | f2p 部分通过 |
| **1.0** | **178** | **10.5%** | 全部 F2P 通过 |

**GRPO 组级（关键指标）**：

```
组数 422 | 全零组 297 = 70%（advantage ≡ 0 → 零梯度）
组内正样本数：0 个:297 组 | 1 个:75 | 2 个:27 | 3 个:9 | 4 个:14
→ 只有 125 组（30%）提供梯度信号，其中 60% 是最弱的"1 正 3 负"
```

### 2.2 训练曲线（通过率先升后降）

| step 段 | 轨迹数 | reward | 通过率 |
|---|---|---|---|
| 0-9 | 362 | 0.083 | 6.9% |
| 10-19 | 324 | 0.130 | 11.1% |
| **20-29** | 324 | **0.143** | **13.0%（峰值）** |
| 30-39 | 324 | 0.133 | 12.0% |
| 40-49 | 280 | 0.099 | **8.9%（-31% 回落）** |

### 2.3 行为指标演化（训练的真实收益）

| 指标 | step 0-9 | step 40-49 | 变化 |
|---|---|---|---|
| 格式错误/轨迹 | 0.40 | 0.05 | **↓ 88%** |
| 有效动作数 | 9.70 | 10.49 | ↑ 8% |
| 编辑次数 | 0.88 | 1.06 | ↑ 21% |
| 测试执行 | 1.45 | 1.88 | ↑ 30% |

**模型学会了"怎么工作"（格式、编辑、测试），但没学会"解对题"**——行为改善是训练的
真实成果，说明 RL 信号有效，只是被数据难度与奖励稀疏截断了上限。

### 2.4 训练健康度与两处异常

| 指标 | 正常区间 | 异常 |
|---|---|---|
| `actor/entropy` | 0.33-0.45（健康，无塌缩） | — |
| `actor/kl_loss` | 0.0046-0.0062（稳定） | — |
| `response_length/clip_ratio` | — | **12.5%-18.8% 的响应触顶被截断** |
| `actor/grad_norm` | 0.014-0.038 | **step 41: 7.53 / 44: 8.01 / 45: 5.94（300 倍爆炸）** |

**梯度爆炸事故（本次复盘最重要的事故发现）**：

```
step 40: grad_norm 0.026, reward 0.094   ← 正常
step 41: grad_norm 7.534, reward 0.000   ← 爆炸（全零奖励步）
step 44: grad_norm 8.011, reward 0.000   ← 爆炸
step 45: grad_norm 5.937, reward 0.125   ← 爆炸
→ step 40-49 通过率回落至 8.9%（峰值 13.0%）
```

**机制**：全零奖励步的 pg 梯度应为零，但 KL 正则项的梯度仍在——当 batch 内
完全没有优势信号时，**优化方向只剩"向 reference 收缩"**，而某一步的 KL 梯度
异常放大（或存在未裁剪的离群样本梯度）→ 一次大更新破坏策略。

---

## 3. reward=0 的五类根因（按贡献量化）

> 互斥归类（n=1480 条零奖励轨迹），优先级：基建 > 幻觉提交 > 格式崩溃 > 只读 > 截断 > 试错

| 类别 | 轨迹数 | 占比 | 代表案例 |
|---|---|---|---|
| **R2 状态表示问题**（只读瘫痪） | **765** | **51.7%** | step-0/mypy-15131 |
| **R5 环境反馈缺失**（试错未成） | **432** | **29.2%** | step-0/conan-14177 |
| **R4 超参数配置不当**（token 截断） | **179** | **12.1%** | step-1/mypy-11824 |
| **R1 奖励函数设计缺陷**（幻觉提交） | 65 | 4.4% | step-1/mypy-5617 |
| R6 基础设施（启动失败/异常终止） | 29 | 2.0% | step-0/conan-14177 |
| **R3 动作空间限制**（格式崩溃） | 10 | 0.7% | step-1/conan-10408 |

### R1 · 奖励函数设计缺陷（4.4% 直接 + 70% 全零组）

**证据**：
- **70% 的组零梯度**——`reward = f2p_passed/(passed+failed)` 为纯轨迹级稀疏奖励，
  n=4 × 20 题（每步 8 题）在 87.5% 零奖励下无法保证组内正负样本并存；
- **65 条"幻觉提交"**（submit 但补丁=0）：模型宣布完成而实际无改动，
  **环境不拒绝**（submit 门槛只有 `operations >= 3`，不校验是否真的改过文件）——
  无效动作获得"正常结束"的假反馈；
- **无任何过程奖励**：episode 内每步 reward 恒 0（`record["steps"].append({... "reward": 0.0 ...})`），
  51.7% 的只读轨迹在 12 轮里得不到任何"该动手了"的信号。

**调整方案**：

| 参数/位置 | 现值 | 调整方向 | 目标值 |
|---|---|---|---|
| `algorithm.filter_groups.enable` | 未设置（等价 False） | **开启**（DAPO 式组过滤：全对/全错组丢弃重采样） | `True` |
| `algorithm.filter_groups.metric` | — | 指定 | `acc` |
| `algorithm.filter_groups.max_num_gen_batches` | — | 限制重采样轮数（控制成本） | `5` |
| submit 门槛（`swe_agent_loop.py`） | `operations >= 3` | **加"必须有文件改动"**（`changed_files > 0`），否则拒收并提示 | `ops>=3 AND changed>0` |
| 过程奖励（可选） | 无 | 编辑/测试动作给微量 shaping（如 +0.01/次，上限 0.05） | 探索期启用 |

### R2 · 状态表示问题（51.7%）

**证据**：
- **765 条轨迹 0 次编辑**（占零奖励的 51.7%）——模型读了 10-12 轮、每轮"更深入理解"，
  但**从不动手**（典型指纹：`T1 I0 I0 I0 ... I0` 12 轮全读）；
- **根因链**（三层叠加）：
  1. **system prompt 缺失行动纪律**——现有模板（`data/train.parquet` 原始版本，337 字符）：
     > "You are an autonomous software engineer ... output EXACTLY ONE bash command ... When you believe the issue is fixed, output: SUBMIT"
     只有"做什么"，**没有"做多少"**：不告知 12 轮预算、不要求"尽早编辑"、不禁止反复读；
  2. **无轮次意识**：`max_steps=12` 是环境侧参数，模型无从知晓（第 11 轮仍在 `Let me examine...`）；
  3. **observation 截断 512 tokens**（`bounded_observation`，头 1/4 + 尾 3/4）——
     大文件读不全 → 模型反复读同一文件换角度（增量信息为 0 的循环）。
- **编辑时机数据**：成功组首编辑中位第 5 轮；失败组两极（第 1 轮瞎改 76 条 / 11-12 轮才动 67 条）——
  **"在第 2-5 轮进入编辑"是成功的关键行为**，而当前 prompt 不施加此约束。

**调整方案**：

| 参数/位置 | 现值 | 调整方向 | 目标值 |
|---|---|---|---|
| **system prompt**（数据集构造侧） | 337 字符，无纪律 | **重写**：加"预算 12 轮 + 读 2-3 次内必须尝试编辑 + 禁止重复读同一文件" | 见下方模板 |
| `observation_tokens`（`configs/swe_agent.yaml`） | 512 | 提高（大文件读取完整） | `768-1024` |
| `max_steps` | 12 | 保持（纪律靠 prompt，不靠减轮数） | 12 |
| `bounded_observation` 策略（`action_protocol.py`） | 头 1/4 + 尾 3/4 | 改为"**错误优先**"：pytest 失败段全保留 | 结构化截断 |

**prompt 模板建议**（追加到 system，~120 字符）：

```
You have a budget of 12 commands. Inspect at most 3 times, then make your edit.
Never repeat a command already run. If three edits fail, reconsider your approach.
```

### R3 · 动作空间限制（0.7% 直接，但污染 10.4% 的执行）

**证据**：
- `parse_action`（`sandbox/action_protocol.py:5`）为**宽松模式**——含 ``` 块取第一块、
  **无块则整段当脚本执行** → 散文被当作命令（exit 127 占所有步的 10.4%）；
- 21.6% 的轨迹 ≥50% 轮次格式错误（早期；随训练降至 ~0），说明模型对格式的遵从
  在长上下文中退化，而**宽松解析掩盖了错误**（模型不因散文受罚，也没学到"必须用 bash 块"）；
- 成功与失败轨迹**都带格式税**（成功组也有 25% 的格式问题轮次）——格式不是判决，是摩擦。

**调整方案**：

| 参数/位置 | 现值 | 调整方向 | 目标值 |
|---|---|---|---|
| `parse_action` 裸文本路径 | 整段执行 | **收紧**：无 fenced block → 直接 `format_error`（附提示），不执行 | 严格模式 |
| 格式错误 observation | 通用提示 | 附**正确格式样例**（few-shot 纠正） | 含样例 |
| `action_tokens` | 2048 | 保持（思考 + 命令空间足够） | 2048 |

### R4 · 超参数配置不当（12.1% 直接 + 训练效率损失）

**证据**：
- **179 条训练轨迹被 token 预算截断**（`stop_reason=token_budget`，12.1%）——
  `data.max_response_length=8192` 而**评估侧实际用 16384**，训练预算只有一半；
- **45 步中 12.5-18.8% 的响应触顶**（`clip_ratio`）——每 6 条轨迹就有 1 条被强制截断；
- **梯度裁剪未显式配置**（默认 1.0，实测 grad_norm 达 8.0）→ §2.4 的爆炸事故；
- **LoRA r=32 attention-only**（`target_modules=[q,k,v,o]`）——43% 的失败是"改了但方向错"，
  表达力可能是瓶颈之一（对照实验：all-linear）；
- lr=1e-5 偏保守（grad_norm 长期 0.02 量级——更新幅度极小）；
- `sandbox_concurrency=8` 而每步需 32 条 rollout 并发 → rollout 排队（step 耗时 12.8 分钟）。

**调整方案**：

| 参数 | 现值 | 调整方向 | 目标值 |
|---|---|---|---|
| `data.max_response_length` | 8192 | **×2** | `16384` |
| `actor_rollout_ref.rollout.max_num_batched_tokens` | 8192 | ×2 | `16384` |
| `actor_rollout_ref.rollout.max_model_len` | 16384 | ×2（与 response 对齐有余量） | `32768` |
| `actor_rollout_ref.actor.clip_grad` | 默认 1.0 | **显式设置并收紧** | `0.5` |
| `actor_rollout_ref.actor.optim.lr` | 1e-5 | ↑ | `3e-5` |
| `actor_rollout_ref.model.target_modules` | `[q,k,v,o]` | 扩展 | `all-linear` |
| `actor_rollout_ref.rollout.n` | 4 | ×2 | `8` |
| `data.train_batch_size` | 8 | ×2 | `16` |
| `actor_rollout_ref.actor.kl_loss_coef` | 0.001 | ↓（防全零步的 KL-only 漂移） | `0.0005` |
| `trainer.total_training_steps` | 50 | ×3 | `150` |
| `trainer.test_freq` / `save_freq` | 10 | ↑（降评估开销） | `25` |
| `sandbox_concurrency`（`swe_agent.yaml`） | 8 | ×2 | `16` |
| 训练数据 | 20 题（tier0 全量） | **画像筛选 + 扩池** | 40-60 题，p̂∈[0.25,0.75] 占 ≥60% |

### R5 · 环境反馈缺失（29.2%）

**证据**：
- **432 条"试错未成"**——有编辑、有测试，但反复 `edit → test x1 → edit → test x1` 直到轮次耗尽
  （典型：`T1 I0 T1 I0 T1 I0 D1 I0 T1 D1 D0 T1`）；
- **测试反馈的信息密度低**：observation 只有原始 pytest 输出（截断 512），
  模型拿不到"当前失败的是哪个断言、和上次比变了什么"的结构化信号；
- **无跨轮记忆辅助**：模型不记得自己改过什么（幻觉提交的温床——65 条以为改过、实际 0 改动）；
- **失败模式无区分**：编辑失败与命令失败的反馈形态相同（都是 exit_code + 文本）。

**调整方案**：

| 参数/位置 | 现值 | 调整方向 | 目标值 |
|---|---|---|---|
| `observation_tokens` | 512 | ↑（与 R2 共用） | `768-1024` |
| 测试 observation 头部 | 原样输出 | **加结构化摘要头**：`[FAILED: N] first_failure: <test>::<assert 简摘>` | 每轮 3 行摘要 |
| 跨轮状态提示 | 无 | 每轮 observation 尾部附 `changed_files=[...]` 一行（消除"幻觉已改"） | 启用 |
| submit 拒绝反馈 | 无 | 空提交被拒时返回 `No files changed; your edits did not take effect` | 启用 |

### R6 · 基础设施（2.0%）

**证据**：10 条空 episode（沙箱创建失败）+ 19 条异常终止（`stop_reason=None`，2-3 轮后消失）。

**调整方案**：沙箱创建失败重试 3 次（指数退避）；失败样本标记 `failure_kind=infra` 并
从 batch 剔除（不计入零奖励统计，避免污染组均值）。

---

## 4. 五类根因的结构关系（为什么只改一处不够）

```
                    ┌──────────────────────────────┐
                    │  R1 奖励稀疏（70% 组零梯度）    │
                    └──────────────┬───────────────┘
                                   │ 无信号
     ┌─────────────────────────────┼─────────────────────────────┐
     ▼                             ▼                             ▼
┌─────────┐                 ┌─────────┐                  ┌─────────┐
│ R2 只读  │◄── prompt 无 ────│ 模型行为 │── 预算不足 ─────►│ R4 截断  │
│ 51.7%   │    纪律约束      │         │                  │ 12.1%   │
└─────────┘                 └────┬────┘                  └─────────┘
                                 │ 反馈贫瘠
                                 ▼
                      ┌────────────────────┐
                      │ R5 试错无引导 29.2% │
                      └────────────────────┘
     R3 格式摩擦（10.4% 无效执行）+ R6 基建（2.0%）——交叉污染项
```

**关键依赖**：数据筛选（R1/R5）和 prompt 纪律（R2）**必须同时做**——
只筛数据不改 prompt，模型仍会把"可做对的题"做成全零；只改 prompt 不换数据，
梯度信号密度不足以支撑 150 步。

---

## 5. 下一轮训练配置变更清单（总表）

### 5.1 数据（最高优先级）

| # | 项 | 现值 | 新值 | 依据 | 预期效果 |
|---|---|---|---|---|---|
| D1 | 训练题池 | 20 题（未筛选） | **40-60 题**（画像筛选后） | 全零组 70% | 全零组 ≤45% |
| D2 | 筛选标准 | 无 | 独立 driver 跑 **pass@4 画像**，保留 p̂∈[0.25,0.75] 的题（≥60% 占比） | pass@4 实测 15% 中位难度带 | 每步有效组 ≥5 |
| D3 | system prompt | 337 字符（无纪律） | 重写（预算 + 行动纪律，见 §3-R2） | 只读 51.7% | 只读 ≤25% |

### 5.2 训练超参

| # | 参数 | 现值 | 新值 | 依据 |
|---|---|---|---|---|
| H1 | `data.max_response_length` | 8192 | **16384** | 截断 12.1% + clip 19% |
| H2 | `rollout.max_model_len` | 16384 | 32768 | 与 H1 对齐 |
| H3 | `rollout.max_num_batched_tokens` | 8192 | 16384 | 与 H1 对齐 |
| H4 | `rollout.n` | 4 | **8** | 组内信号捕获 ×2 |
| H5 | `data.train_batch_size` | 8 | **16** | 每步组数 ×2 |
| H6 | `actor.optim.lr` | 1e-5 | 3e-5 | grad_norm 长期 0.02 |
| H7 | `actor.clip_grad` | 默认 1.0 | **0.5（显式）** | grad 爆炸 8.0 |
| H8 | `actor.kl_loss_coef` | 0.001 | 0.0005 | 全零步 KL-only 漂移 |
| H9 | `target_modules` | q,k,v,o | all-linear | 表达力 |
| H10 | `kl_loss`（算法） | use_kl_loss=True | True（保留，降权） | entropy 健康 |
| H11 | `trainer.total_training_steps` | 50 | **150** | 数据×n 扩容后 |
| H12 | `trainer.test_freq`/`save_freq` | 10 | 25 | 评估成本 |
| H13 | `algorithm.filter_groups.enable` | False | **True**（metric=acc, max_gen_batches=5） | 全零组 70% |
| H14 | `sandbox_concurrency` | 8 | 16 | rollout 排队（step 12.8 分钟） |

### 5.3 行为与反馈（代码改动）

| # | 位置 | 改动 | 目标 |
|---|---|---|---|
| B1 | `action_protocol.parse_action` | 无 fenced block → 拒绝执行（format_error + 样例提示） | 无效执行 10.4% → 0 |
| B2 | `swe_agent_loop` submit 门槛 | `ops>=3 AND changed_files>0` | 幻觉提交 65 条 → 0 |
| B3 | 测试 observation | 加 3 行结构化摘要（失败数 + 首失败 + 变化） | R5 试错引导 |
| B4 | 每轮 observation 尾 | 附 `changed_files=[...]` 状态行 | 消除"幻觉已改" |
| B5 | 沙箱创建 | 重试 3 次（指数退避） | R6 2% → <0.5% |
| B6 | 全零组处理 | 与 H13 配合：重采样后仍全零的组标记 `skipped_zero_group`，从 loss 剔除 | 防 KL-only 更新 |

### 5.4 预期效果（可验证）

| 指标 | 现状 | 目标 | 验证方式 |
|---|---|---|---|
| 全零组占比 | 70% | **≤45%** | 每步 trace 统计（`traces_by_step.csv`） |
| 只读瘫痪（0 编辑） | 51.7% | **≤25%** | 症状归类脚本 |
| token 截断 | 12.1% | **<2%** | `stop_reason` 统计 |
| 无效执行（exit 127） | 10.4% | **<1%** | exit_code 统计 |
| 幻觉提交 | 65 条 | **0** | patch=0 且 submit 计数 |
| grad_norm 异常（>1） | 3 步 | **0** | metrics.csv |
| 训练通过率曲线 | 0.08→0.14→0.09 | **单调上升至 ≥0.25**（step 150） | traces_by_step.csv |
| pass@4（40 题评估） | 15% | **≥25%** | 独立 vLLM driver |

### 5.5 验证节奏

```
① 画像筛选（零 GPU，AGS 4-6h）→ 确定题池（门槛：p̂∈[0.25,0.75] 的题 ≥24 道）
② 冒烟 10 步（验证 prompt/解析器/反馈改动生效：只读率、无效执行、幻觉提交三项归零）
③ 主训练 150 步（每 25 步 driver 评估，连续 50 步无提升即早停）
④ 终评 pass@4（同 40 题协议）→ 与 15% 基线对照
```

---

## 6. 风险与备选

| 风险 | 概率 | 缓解 |
|---|---|---|
| 画像筛选后题池 <24 道 | 中 | 触发扩池（Swe-Gym 其他 repo 建镜像，1-2 天）；备选：降低门槛至 p̂∈[0.1,0.9] |
| `filter_groups` 使 rollout 成本 ×2-3 | 高 | `max_num_gen_batches=5` 封顶；配合 H4（n=8）时观察实际吞吐 |
| response 16384 导致显存紧张 | 中 | 训练侧 `gpu_memory_utilization=0.5` 有上调余量；必要时 `max_num_batched_tokens` 保持 8192 |
| all-linear LoRA 显存增长 | 中 | 监控 actor 显存；回退 q/k/v/o + 提高 lr |
| prompt 纪律过强导致"乱改" | 低 | 保留"读 3 次"下限；观察首编辑轮次分布（目标中位 3-5 轮） |

---

## 附录 A：关键证据索引

| 证据 | 位置 |
|---|---|
| 症状分类学（8 簇 / "说而不做" 50.6%） | `docs/validation/trajectory-symptom-study.md` |
| pass@4 评估（base 15% / lora 10%） | `docs/validation/pass4-test-design-postmortem.md` |
| 训练指标快照 | `docs/training-runs/run-07-swegym-30b-tier0-r1/report/metrics/{metrics,traces_by_step}.csv` |
| 落盘代码（每步 tracing + DataProto 对齐） | `verl_plugin/swe_agent_loop.py:130,208-231` |
| 动作协议（宽松解析 + 截断） | `sandbox/action_protocol.py:5,76` |
| AgentLoop 参数 | `configs/swe_agent.yaml` |
| 训练超参 | `configs/grpo_4l20_30b.sh` |
| 轨迹归档（1692 条） | `artifacts/archive/cfs-traces-30b/swegym-30b-tier0-r1.tar.gz` |

## 附录 B：本次复盘中修正的两个认知

1. **"训练没效果"是不准确的**——行为指标（格式/编辑/测试）显著改善，训练信号有效；
   失败在于**信号密度不足以穿越数据难度壁垒**；
2. **"加步数就好"是错的**——50 步里 70% 的步零梯度，grad 爆炸还破坏了峰值策略；
   不解决数据与 KL-only 漂移，150 步只会更贵地复现同一条曲线。
