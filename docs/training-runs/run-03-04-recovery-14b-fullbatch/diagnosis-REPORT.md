# GRPO 零奖励/零优势诊断报告（诊断路径执行结果）

日期：2026-09-11　方法：只读取证 + CPU 隔离回放（冻结源码 verl 0.10.0.dev + 实际运行 kit）
未修改正式奖励代码、未重启训练、未删除任何产物。

## 结论

**已记录的零优势步（round0 步 1–8、adapter-v2-warmup 步 1–2）是"奖励确实全零"的正确算法结果，不是优势计算或奖励传递缺陷。**
而最新两轮已产生正奖励的 fullbatch 运行，从未到达参数更新——被流水线的 fatal-log 检测在判分器 RuntimeError 处终止。

## 六步路径执行记录

### 1. 确认是否真的全零 —— 是（对已记录步）

| 运行 | 已记录训练步 | score/max | adv/max | grad_norm |
|---|---|---|---|---|
| round0-train (7B) | 1–8 | 0.0 | 0.0 | 0.0 |
| recovery-14b-adapter-v2-warmup | 1–2 | 0.0 | 0.0 | 0.0 |
| recovery-14b-fullbatch-v2/v3 | 0（仅验证步） | — | — | — |

三者链路一致：奖励 0 → 优势 0 → 梯度 0。无"score>0 但 adv=0"的断链证据。
fullbatch 两轮在 step-1 更新前被停止（pipeline result.json: status=stopped, fatal_log=true）。

### 2. 评奖器区分度 —— 通过

9/9 已验证实例：baseline=[0.0, 0.0]、golden=[1.0, 1.0]（双次重复一致）。
pylint-4551 被正确 skip（baseline 收集 ImportError）。评奖器能区分好坏补丁。

### 3. 奖励传递对齐 —— 逐段核验通过

代码链（冻结源码）：
`final["reward"]`（judge）→ `AgentLoopOutput.reward_score`（swe_agent_loop.py:198）
→ `_postprocess` 在最后一个有效 token 写入 `rm_scores`（agent_loop.py:1062–1068）
→ `extract_reward` 直取 `rm_scores`（reward.py:160–167）
→ `token_level_scores` →（use_kl_in_reward=False）`token_level_rewards`
→ GRPO `scores = token_level_rewards.sum(-1)`（core_algos.py:304）。

经验证据：pilot 12 条轨迹 1 条满分 → `val-aux/.../reward/mean@2 = 0.0833`；
fullbatch-v2 评估 1/12 → 0.0833；round0 评估 1/12 → 0.0833。数字与轨迹完全吻合。

合成填充（padding_utils.py）：独立 uid、response_mask 全零、奖励零，不污染真实分组
（隔离验证 pad-group 优势恒 0）。

### 4. 真实组内奖励 —— 已重建全部分组

有信号的组（update 本应发生）：
- fullbatch-v2 step-1 django__django-12286: [0.0, 1.0, 0.0]（1 条样本因判分 RuntimeError 被丢弃）
- fullbatch-v3 step-1 django__django-11039: [0.0, 1.0, 1.0, 1.0]（同上丢弃 1 条）

round0 与 warmup 的全部训练组：组内奖励全 0（错误样本被丢弃后仍无差异）。

### 5. 隔离测试优势计算（冻结函数，CPU torch 2.8）—— 算法正确

| 组内奖励 | 优势 |
|---|---|
| [0,1] | [-0.707, +0.707] |
| [0,0] | [0,0]（预期） |
| [1,1] | [0,0]（预期：全对同全错一样无相对信号） |
| [0.333,0] | [+0.707,-0.707] |
| 单例[1] / 单例[0] | [1.0] / [0.0]（verl 单例组特例：adv=原始分） |
| **v2 真实组 [0,1,0]** | **[-0.577, +1.155, -0.577]** |
| **v3 真实组 [0,1,1,1]** | **[-1.5, +0.5, +0.5, +0.5]** |

即：只要真实奖励进入批次，冻结的 GRPO 实现必然产生非零优势。

### 6. 更新链路 —— 一致且（隔离验证）可产生梯度

- 已记录步：grad_norm=0 恰好出现在 adv=0 的步，无优化器异常迹象。
- KL：use_kl_loss=True（coef 0.001），step-1 kl_loss=0（初始 ref==old，预期）。
- 隔离验证（真实 episode mask + 奖励 1.0，old_log_prob detach）：
  adv=1.0 → pg_loss=-1.0 → **梯度非零**（|grad| 总和 1.0，落在 mask 有效 token 上）。
- 检查点：仅 adapter-v2 有 step1/2 checkpoint；fullbatch 死于首个 checkpoint 之前。

## 根因链（按时间顺序）

1. **round0（7B）与 warmup（14B）零优势**：所有被采样组内奖励全零。
   促成因素：模型可解任务极稀疏（pilot 仅 django-11039 可解，1/12）；
   batch=4/6 采样两步均未采到 django-11039；n=2 组内出现差异概率低。
   → 零优势是这些输入下的正确输出。
2. **fullbatch-v2 中断**：判分器因 Django subTest 名拼接（`test_a ... test_b ... ok`）
   报 missing 1 test → RuntimeError。v2 kit 缺少 `normalize_django_states`（v3 kit 已有）。
3. **fullbatch-v3 中断（当前阻塞）**：模型补丁破坏 Django system check
   （`SystemCheckError: translation.E004`），测试从未运行 → "Incomplete evaluation"。
   `candidate_error` 正则（SyntaxError/IndentationError/ImportError/ModuleNotFoundError/
   collection errors）不覆盖框架级系统检查失败 → 抛异常而非记 0 分。
   episode 失败 → 流水线 fatal-log 检测停止整个运行 → 带信号的更新从未发生。
4. round0 的 9 例 "Required tests absent" 属同类（旧版严格校验），同样引发丢弃/停止。

## 建议修复（按优先级）

1. **判分器稳健化**：marker 完整、exit≤2 但测试未运行时，扩展候选错误识别
   （含 SystemCheckError 等"套件启动前失败"），先跑无补丁对照确认基线可收集，
   再记 reward=0 + failure_kind，而不是抛 RuntimeError。
2. **AgentLoop 容错**：judge 抛异常时按 0 分 + failure_kind 落盘并返回样本，
   避免单条 episode 让整轮训练被 fatal-log 检测终止（或放宽 watcher 判据）。
3. 确保运行使用含 `normalize_django_states` 的 kit（v3+）。
4. 保持 fullbatch 配置方向（batch=6 覆盖全部题、n=4 增大组内差异概率）。

## 证据位置

- 快照：`artifacts/grpo-diagnosis-20260911/evidence/{logs,traces,validation}`
- 冻结源码：`.../frozen_source/verl`、`.../frozen_kit_v3`
- 隔离测试：`.../isolated_test.py` → `.../isolated_report.json`
- 运行时配置：`.../runtime-config.json`（自日志解析的最终 Hydra 配置）
