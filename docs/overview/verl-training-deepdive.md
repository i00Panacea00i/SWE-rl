# verl 强化学习训练全流程深度复盘（基于 2092 条真实 trace）

> **证据基础**：1692 条训练轨迹（`artifacts/archive/cfs-traces-30b/`，51 个 step，
> 17657 个交互轮次）+ 400 条评估轨迹 + 完整训练日志（6546 行）+
> 45 条步级指标（`reports/swegym-30b-tier0-r1/metrics/`）。
> **引用约定**：`[E1]`~`[E12]` 对应文末证据索引；所有数字均可回溯到原始文件。

---

## 1. 训练任务编排：从启动到结束

### 1.1 六阶段生命周期（触发条件与状态流转）

```
① 环境装配（~3 分钟）
   pip 安装依赖链 [E1: 日志 L1-230]
   → 引擎探测（torchtitan/veomni/automodel 均不可用 → 回退 FSDP）[E1: L239-244]
② 配置冻结与打印（~1 分钟）
   → 完整配置 dump（可审计）[E1: L245+]
   → ⚠ critic 禁用确认："Disabled critic as algorithm.adv_estimator != gae" [E1: L234]
③ 模型与引擎初始化（~5 分钟）
   → FSDP actor：Before 0.29GB → After allocated 14.23 / reserved 16.56 / used 17.02 (44.39GB) [E1: L1271-1277]
   → vLLM 启动：模型加载 16.84 GiB / 5.83s（TP=4 分片后）[E1: L1426]
④ 训练主循环（50 步 × 770-840s ≈ 11 小时纯训练）
   每步：rollout(生成+沙箱) → old_log_prob → ref → adv → update_actor → (每10步) val → (每5/10步) save
⑤ 周期评估（val_before_train + 每 10 步）：val 用 2 题 / 每步耗时 306s [E2: step-50 timing]
⑥ 收尾（最终 val + 最终指标）
   "Final validation metrics: {'val-aux/.../reward/mean@1': 0.5, 'val-core/.../acc/mean@1': 0.5}" [E1: 尾部]
```

### 1.2 单步内部的精确时序（step-50 实测，[E2] timing_s/*）

| 阶段 | 耗时 | 占比 | 说明 |
|---|---|---|---|
| **gen（生成+沙箱交互）** | **619.3 s** | **80.5%** | 含 vLLM 生成 + AGS 沙箱执行 |
| update_actor（参数更新） | 74.6 s | 9.7% | 含反向传播 |
| old_log_prob / ref | 30.8 / 29.9 s | 7.9% | 两项前向 |
| testing（val，仅每 10 步） | 306.3 s | — | 单独统计 |
| save_checkpoint | 11.4 s | 1.5% | LoRA-only |
| **update_weights（同步到 vLLM）** | **3.4 s** | **0.4%** | layered_summon 逐单元同步（≤1.2MB/单元） |
| adv（优势计算） | **0.055 s** | ~0% | 纯 CPU 张量运算 |
| **合计/步** | **769.5 s** | 100% | throughput 61.9 token/s |

### 1.3 状态流转的关键证据

- **训练/评估/保存的调度**：`save_freq` 每 5 步（166MB/个）、`test_freq` 每 10 步、
  `val_before_train` 开启（metrics 有 val 值）[E2/E3]
- **无 off-policy 陈旧**：`training/off_policy/trajectory_staleness: 0.0`（同步训练，
  rollout 与更新严格交替）[E2]
- **数据重复度**：`training/epoch: 24`（50 步 × 8 题 ÷ 20 题池 ≈ 每题平均被见 20 次）[E2]

---

## 2. 数据链路：从采样到训练的完整链路

### 2.1 端到端数据流

```
① prompt 构造（离线）：task_specs + 题面 → parquet（prompt + extra_info）
② rollout 采样：8 题 × n=4 = 32 条/步（vLLM 生成 → 解析 → AGS 沙箱执行 → 观察回传）
③ 轨迹落盘（本复盘的核心对象）：
   traces/<run>/<phase>/step-<N>/<instance_id>/<episode_id>/
   ├─ episode.json        ← 完整过程（含 token 级数据）
   ├─ candidate.patch     ← 净产出
   ├─ agent/execution.json← 命令级证据
   └─ judge/              ← 判分（result.json + test.log）
④ 判分与奖励回填：judge 结果 → extra_info["swe_evaluation"] → reward.py → GRPO score
⑤ 训练消费：token_alignment（prompt_ids + action_token_ids 逐轮）→ actor 前向/反向
```

### 2.2 episode.json 的完整数据结构（训练轨迹，真实 schema）

**顶层字段**（[E4]）：
```
episode_id / instance_id / tool_name / model / base_commit / phase(全部=train)
global_step / split / started_at / finished_at / agent_kind(model_generated)
gold_patch_visible: False     ← 防泄漏断言 ✓
sandbox_id / sandbox_mode(image_override) / fingerprint
steps[]（≤12 项）/ shell_operations / meets_min_steps
operation_kinds: {execute: 11, inspect: 1}
stop_reason: step_budget | token_budget | submit
changed_files / final
```

**每轮（steps[i]）的字段**（训练数据的最小单元）：
```
step / kind(execute|inspect) / action(模型原文) / executed_command(实际执行)
observation(完整回传) / observation_in_context(截断后——进入上下文)
reward / done / exit_code
action_token_ids[]   ← ★ token 级记录（训练直接消费）
```

> **关键机制**：`observation`（完整）与 `observation_in_context`（截断）双轨存储——
> 后者按 `observation_tokens=512` 截断，**这就是 token 预算管理在 trace 中的直接体现**。

### 2.3 全量操作统计（1692 条 / 17657 轮次，[E5]）

| 操作类型 | 次数 | 占比 |
|---|---|---|
| inspect（读代码） | 8206 | 46.5% |
| execute（执行） | 4499 | 25.5% |
| test（跑测试） | 3014 | 17.1% |
| edit（编辑） | 1577 | 8.9% |
| format_error | 161 | 0.9% |
| submit | 125 | 0.7% |

**单轮 exit_code 分布**（29053 次命令执行，[E5]）：
`0: 9113 (31.4%) | 1: 3389 (11.7%) | 127: 3017 (10.4%) | 2: 1923 (6.6%) | 126: 89 | 5: 63`

---

## 3. 模型角色的分工、更新与同步

### 3.1 四个角色的实际配置（[E1] 日志配置 dump + 运行痕迹）

| 角色 | 是否启用 | 显存/资源 | 职责 |
|---|---|---|---|
| **actor（策略模型）** | ✅ | FSDP 分片 15.3GB + 缓冲；**峰值 allocated 23.4 / reserved 26.1 GB** [E2 step-10] | 生成 + 更新 |
| **ref（参考模型）** | ✅ | param_offload=True（CPU 常驻） | KL 计算（kl_loss_coef=0.001）|
| **critic（价值模型）** | ❌ **禁用** | — | 官方日志："Disabled critic as algorithm.adv_estimator != gae" [E1: L234]——**GRPO 用组内标准化替代价值函数** |
| rollout（vLLM） | ✅ | TP=4，权重 16.84GB/卡，util 0.5 | 高速生成 |

### 3.2 参数更新与同步机制（每步闭环）

```
① rollout（vLLM 持有权重 v_t 生成 32 条轨迹）
② old_log_prob / ref（用 v_t 计算旧策略概率与参考概率）
③ adv（组内标准化 → ±1.5 范围）[E2: advantages/max=1.5]
④ update_actor（actor 的 LoRA 参数更新，74.6s）
⑤ update_weights：actor 新权重 → vLLM（layered_summon 逐单元 ≤1.2MB，3.4s）
   bucket 配置：update_weights_bucket_megabytes=2048 [E1: L563]
⑥ 一致性验证：rollout_corr/kl=0.0049（新旧策略 KL 极小）[E2]
```

**同步正确性的直接证据**：`training/rollout_probs_diff_valid: 1.0`（策略一致性检查通过）、
`rollout_actor_probs_pearson_corr: 0.994` [E2]。

### 3.3 更新量的真实测量（解释"训练无明显效果"）

```
actor/grad_norm: 0.018（step-10）→ 0.024（step-50）
actor/lr: 1e-05
→ 实际参数更新量 ≈ 0.02 × 1e-5 = 2e-7 / 步
→ 50 步累积 ≈ 1e-5 量级——对 32 秩 LoRA 而言几乎可忽略
佐证：actor/kl_loss 仅 0.005（训练前后模型几乎未偏离基模）
     rollout_corr/kl 0.0049（策略漂移极小）
```

---

## 4. 算法模块的执行记录与调用关系

### 4.1 奖励计算（三级链路，可追溯）

```
AGS 沙箱判分（官方测试）
  → judge/result.json：f2p_passed / f2p_failed / resolved [E6 样本]
  → reward = |f2p_passed| / |f2p 总数|（0~1 连续比例奖励）[E7: harness.compute_reward]
  → 经 extra_info["swe_evaluation"] 回填（reward.py 强制校验：缺失即抛错，无文本回退）
  → GRPO score（critic/score/mean: 0.125→0.156）[E2]
```

### 4.2 优势估计（GRPO 组内标准化）

- **组结构**：同题 4 条轨迹为一组（n=4），组内标准化
- **实测分布**：`advantages/max: 1.5 / min: -1.5 / mean: ±0.01` [E2]
  —— 极端值 ±1.5 说明组内存在"全对/全错"的判别性极化
- **执行成本**：`timing_s/adv: 0.055s`（**纯张量运算，瞬时完成**）

### 4.3 损失与 PPO 机制

| 指标 | 实测 | 含义 |
|---|---|---|
| `actor/kl_loss` | 0.005 | KL 惩罚实际生效但极小 |
| `actor/pg_clipfrac` | **0.0** | **PPO clipping 从未触发**——策略更新幅度远低于 clip 阈值 |
| `actor/ppo_kl` | 0.0 | 同上 |
| `actor/entropy` | 0.385（step-10） | 极低（正常 1-3）——策略分布接近确定 |
| `entropy_coeff` | **0（配置）** | 无熵正则 [E1] |
| `actor/loss` | -0.015 | |

> **pg_clipfrac=0 的深度含义**：PPO 的裁剪机制形同虚设——**更新幅度太小**，
> 与 §3.3 的 grad×lr 计算完全吻合。

---

## 5. 系统层面：资源调度与显存/内存轨迹

### 5.1 资源布局

| 层级 | 配置 | 实测 |
|---|---|---|
| Ray + TaskRunner | 单节点 4 GPU | `TaskRunnerV1 pid=6534` [E1] |
| FSDP（actor/ref） | world_size=4 | Before 0.29GB → After 17.02GB/卡 [E1: L1271-1277] |
| vLLM | TP=4, util=0.5 | 权重 16.84GB/卡，加载 5.83s [E1: L1426] |
| AGS 沙箱 | 8 agent workers 并发 | 每步 32 条轨迹 |
| CPU 内存 | limit 350Gi | **实测 242.9 → 247.1 GB**（峰值）[E2] |
| dshm | 32Gi | Ray 对象存储 |

### 5.2 关键显存/内存事件

- **actor 峰值显存**：`max_memory_allocated 23.39 / reserved 26.10 GB`（44.39GB 卡的 59%）[E2]
- **vLLM sleep 警告**：`Setting the sleep level to 1 may cause a memory overflow`（×4 卡）[E1: L1282]
- **`multi_stage_wake_up: False`**（单级唤醒——峰值显存的潜在优化点）[E1: L612]
- **expandable_segments 双态**：FSDP 侧 True / vLLM 侧 False（各自适配）[E1: L1369-1428]
- **CPU 内存 247GB**（350Gi 限制的 71%）——历史上 286GB 曾触发 OOM（300Gi 时代）[E8]

### 5.3 算力效率

- **`perf/mfu/actor: 0.158 - 0.160`**（**MFU 仅 16%**，[E2]）——主要被沙箱等待稀释
- `perf/throughput: 61.9 token/s`、`perf/total_num_tokens: 190591/步`

### 5.4 一处口径差异（使用 trace 时需注意）

日志的 `training/num_turns/mean: 21.9`（max 25）**不等于** trace 的交互轮次（max_steps=12）：
- trace 口径（`steps[]`/`shell_operations`）：**动作轮次 ≤ 12** ✓
- 日志口径：推测为**LLM 调用次数**（一轮动作内可能含"生成→解析→重试"多次调用），
  12 × ~1.8 ≈ 21.9 可解释该差异；
- **两者不矛盾**——统计口径不同。引用轮次时以 trace 为准（否则会误判 max_steps 失效）。

---

## 6. 异常、重试与回退（全量统计 + 根因）

### 6.1 轨迹级异常（1692 条全量，[E5]）

| 现象 | 数量 | 占比 | 根因 |
|---|---|---|---|
| **token_budget 截断** | **419** | **24.8%** | **训练预算 8192 不足**（评估侧同题仅 1.9%）——模型输出+观察在 ~10 轮耗尽预算 |
| step_budget 用满 | 1029 | 60.8% | 12 轮上限内未完成（探索效率问题）|
| **"散文主导"轨迹**（≥50% 轮次 exit=127） | **320** | **18.9%** | **模型输出思考文本（无命令块）→ 宽容解析当命令执行 → command not found** |
| 空 episode（steps=0） | 10 | 0.6% | rollout 启动即失败（沙箱创建异常） |
| stop_reason=None | 29 | 1.7% | 异常终止（未写终态） |

### 6.2 重试事件的直接证据（step-1 的 96 条 = 3 次完整 rollout）

```
step-1 目录含 96 条轨迹 = 32 × 3（8 题 × 4 采样 × 3 轮尝试）
时间簇断点：+537s、+952s（三个独立的 32 条批次）[E9]
→ 解释：训练启动后 step-1 经历了 2 次中断 + 1 次成功完成
   （与 resume_mode=auto、启动阶段的多次环境问题吻合）
```

### 6.3 重大事件时间线（结合已知运行记录 [E8]）

| 事件 | 证据 |
|---|---|
| CPU 内存 OOM（286/300GB）发生在 step 5 前后 | [E8] + step-5 目录 34 条（多出 2 条恢复残留）[E5] |
| 修复后从 step 5 无损续训至 50 | 目录完整性（51 个 step × 32 条）[E5] |
| 每步 val（306s）与 checkpoint（11.4s）的周期性开销 | [E2] |

---

## 7. 性能瓶颈、稳定性风险与优化清单

### 7.1 性能瓶颈（按影响排序）

| # | 瓶颈 | 量化 | 优化方向 |
|---|---|---|---|
| 1 | **生成+沙箱占 80.5%**（619s/770s） | 沙箱往返（东京↔新加坡）+ 自回归生成 | 沙箱地域收敛（西部/同区）、生成批量化 |
| 2 | **MFU 仅 16%** | GPU 大量时间在等沙箱 | 提高沙箱并发 / 异步流水 |
| 3 | **token 截断 24.8%** | 419 条轨迹被预算砍断 | 预算 8192→16384（与评估对齐）[见审计文档] |
| 4 | **散文执行浪费 10.4% 轮次** | 3017 次 command not found | prompt 强化输出格式约束 / 解析器改进（拒绝纯散文） |
| 5 | val 开销 306s/次（每 10 步） | 40 分钟总 val 时间 | val 集扩大但降频（每 25 步） |

### 7.2 稳定性风险

1. **CPU 内存 247GB（限 350Gi）**——距 OOM 仅 30% 余量（历史已 OOM 一次）；
2. **更新量过小（2e-7/步）**——grad_norm 0.02 × lr 1e-5（见审计文档 P0-1）；
3. **熵坍缩（entropy 0.385）+ 无熵正则**——探索能力持续衰减；
4. **金标可见性断言**：`gold_patch_visible: False` 全部通过 ✓（无泄漏风险）。

### 7.3 可直接落地的优化清单（按 ROI）

```
P0（重训前）: lr 1e-5→1e-4；target_modules→all-linear；预算 8192→16384；n 4→8
P1（工程）  : 沙箱并发 8→12；多级唤醒 multi_stage_wake_up=True；
             解析器拒绝纯散文（节省 10% 轮次）；entropy_coeff>0
P2（可观测）: 把 token_budget/散文率/空 episode 率纳入训练实时监控（当前只能事后从 trace 统计）
```

---

## 8. 数据流与依赖总图（一页纸）

```
┌─────────────── 离线数据准备 ───────────────┐
│ task_specs + 题面 → parquet(prompt+extra) │
└──────────────────┬────────────────────────┘
                   ▼
┌─────────────── 训练主循环（50 步）───────────────────┐
│ ① vLLM 生成（TP=4）  →  ② AgentLoop 调度（8 workers）│
│ ③ AGS 沙箱执行（命令级 evidence）                    │
│ ④ 轨迹落盘（episode.json + execution + patch）      │
│ ⑤ 判分（独立沙箱）→ result.json → reward 回填        │
│ ⑥ GRPO：组内标准化→advantage→update_actor(74.6s)    │
│ ⑦ update_weights→vLLM（3.4s, layered_summon）        │
└──────────────────┬──────────────────────────────────┘
                   ▼
┌─────────────── 验证与归档 ───────────────┐
│ val（每10步，2题）→ 检查点（每5步）→ 最终模型           │
│ 评估（独立 driver，400 条）→ pass@4 结论                │
└───────────────────────────────────────────┘
```

## 9. 结论（团队复用清单）

1. **编排可复用**：六阶段启动 + 单步 8 组件时序（§1.2）是完整可参考的 verl+AGS 训练范式；
2. **数据契约**：episode.json 的 schema（§2.2）即"轨迹的接口定义"——判分/训练/评估三方共用；
3. **三个必须监控的指标**：`response_length/clip_ratio`（截断率）、`散文率`（新发现）、
   `grad_norm × lr`（实际更新量）——前两者只能从 trace 统计（日志里没有），建议入训练监控；
4. **三个已验证的配置**：FSDP param_offload + layered_summon + vLLM sleep 的组合
   （17GB/卡静态 + 3.4s 同步）；`train_batch=8, n=4` 的最小可行循环；
5. **一条明确的改进主线**：数据难度筛选（85% 题零信号）→ 学习率 ×10 → all-linear →
   预算对齐 → n=8（详见 `training-config-audit.md`）。

---

## 证据索引

| 编号 | 文件 / 来源 | 内容 |
|---|---|---|
| E1 | `reports/swegym-30b-tier0-r1/metrics/train-full.log`（6546 行） | 启动链、配置 dump、显存事件、步级指标 |
| E2 | `reports/swegym-30b-tier0-r1/metrics/metrics.csv`（45 行） | 步级全部指标（含 timing 分解） |
| E3 | 同上 `traces_by_step.csv` / `traces.csv` | 逐步样本数、逐条轨迹摘要 |
| E4 | `artifacts/archive/cfs-traces-30b/traces/.../step-2/.../episode.json` | 训练轨迹 schema |
| E5 | 全量统计脚本输出（1692 条聚合） | stop_reason/exit_code/操作类型分布 |
| E6 | `.../judge/result.json` + `test.log` | 判分证据 |
| E7 | `sandbox/harness.py::compute_reward`；`verl_plugin/reward.py` | 奖励口径与回填 |
| E8 | `docs/training-runs/run-07-.../SUMMARY.md`；`troubleshooting/04` | CPU OOM 事件与恢复 |
| E9 | step-1 的 96 条时间簇分析 | 重试/恢复的直接证据 |
| E10 | `docs/overview/pod-ags-communication.md` | 沙箱通信机制（transfer/execution 细节） |
| E11 | `docs/overview/training-config-audit.md` | 配置审计（16 项问题） |
| E12 | `docs/validation/pass4-test-design-postmortem.md` | 评估协议与结果 |
