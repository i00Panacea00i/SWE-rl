# SandBox 执行 + TKE 训练的 RL 流水线详细报告

> 版本：2026-09-11　|　运行代号：recovery-14b-fullbatch-v4　|　基于实测运行数据编写

---

## 1. 一句话总览

**在 TKE Kubernetes 集群的 2×L20 GPU 上，verl 框架以 GRPO 算法训练 Qwen2.5-Coder-14B 的 LoRA 适配器；每一步采样 6 道 SWE-bench 真实 bug × 4 次，模型在远程 AGS 沙箱（官方评测镜像）里用 shell 命令修 bug，独立判分器按"修复了多少个原本失败的测试"打分，分数经组内归一化变成优势，反传更新策略。**

---

## 2. 系统组件与职责

```
┌─────────────────────────── TKE 集群（节点 <node-ip>）───────────────────────────┐
│                                                                                │
│  ┌──────────────────────┐        ┌──────────────────────────────────────┐      │
│  │ 训练 Pod             │        │ 辅助 Pod（swe-rl-sync）               │      │
│  │ 2×L20 / 32核 / 170Gi │        │ 挂 CFS，供运维检查与产物同步           │      │
│  │ verl + Ray + vLLM    │        └──────────────────────────────────────┘      │
│  │ + FSDP               │                                                       │
│  └─────────┬────────────┘                                                       │
└────────────┼────────────────────────────────────────────────────────────────────┘
             │ ①读提示词/代码        ②创建沙箱、执行命令          ③写训练产物
             ▼                      ▼                            ▼
   ┌──────────────────┐   ┌──────────────────────┐   ┌────────────────────────┐
   │ CFS 共享存储       │   │ AGS 沙箱云            │   │ CFS 训练产物            │
   │ /mnt/cfs/swe-rl/  │   │ ap-singapore          │   │ traces/ checkpoints/   │
   │  kit/（冻结代码）  │   │ <ags-domain>       │   │ logs/ eval_reports/    │
   │  runs/（运行快照） │   │ 10 个沙箱模板          │   └────────────────────────┘
   │  model/（14B权重） │   │ =官方 sweb.eval 镜像  │
   │  verl-src/（框架） │   │（存于 TCR swe-mirror）│
   └──────────────────┘   └──────────────────────┘
```

| 组件 | 规格 | 职责 |
|---|---|---|
| 训练 Pod | verl 官方镜像、2×L20、32 核、170Gi | GRPO 训练全流程（生成+判分调用+更新） |
| AGS 沙箱 | e2b 协议、每实例一个模板 | 隔离执行模型命令与判分（模型代码永不接触训练主机） |
| CFS | PVC `swe-rl-cfs` | 代码快照、权重、轨迹、检查点、日志的持久化 |
| 监视器 | `controller/watch_training.py` | 只读盯日志，发现 Traceback/OOM 即告警停机 |

---

## 3. 数据准备（训练前冻结）

1. **实例集**：`data/instances.jsonl`（10 道 SWE-bench 题）+ `data/task_specs/<题>/`（官方协议：`eval.sh`、`gold.patch`、`test.patch`、`tests.json`）。
2. **环境双向验证**（`sandbox/validate_candidates.py`）：每题在沙箱跑两次 baseline（期望 F2P 全挂=0 分）+ 两次 golden（期望全过=1 分）。**9/9 验证通过**后才允许进训练集。
3. **冻结切分**：`data/prepare_data.py` 生成 train 6 题 / eval 4 题 parquet，含 manifest（每题的镜像、base_commit、协议 SHA256）。
4. **提示词结构**（模型每题看到的内容）：
   - System：动作规则（每轮恰好一条 bash 命令、禁交互编辑器、至少 3 次操作后 SUBMIT）
   - User：GitHub issue 原文 + **修复文件提示** + F2P 测试名 + **可直接运行的测试命令**

---

## 4. 训练 Pod 的启动防护（四道闸）

```bash
① 模型校验   .download-verified.json 逐文件核对大小与 revision
② 协议校验   sha256sum -c protocol.sha256（151 个文件的完整性清单）
③ 路由预检   sandbox.preflight：parquet 里的 tool_name 必须与实例表一致
              （防止"Untrusted sandbox route"在训练中途爆炸）
④ 依赖安装   accelerate / e2b / unidiff / swebench 固定版本
```

---

## 5. 单步训练循环（核心，约 5 分钟/步）

以当前配置（`configs/grpo_l20_lora.sh`）为例，一步 = 6 题 × 4 采样 = **24 条轨迹**：

### 5.1 生成阶段（~3 分钟，`timing_s/gen`）

```
verl TaskRunner
  └─ AgentLoopWorkerTQ（异步，并发 8）
       └─ SWEAgentLoop.run()  ←── 每条轨迹
            1. 创建 AGS 沙箱（模板 = 该题官方镜像）
            2. 校验镜像 HEAD（base_commit 之上恰好一个 "SWE-bench" 构建提交）
            3. 预置目标测试（git apply test.patch）→ 让模型能跑测试拿反馈
            4. 工作树快照（git write-tree）→ 之后导出补丁的基准
            5. 最多 12 轮循环：
                 vLLM 生成 ≤768 token 的动作
                 → parse_action 解析（容忍代码围栏；解析失败记 exit=2 不执行）
                 → 沙箱执行（60s 超时，输出截 32KB 头+尾）
                 → 观察压到 512 token 回填上下文
                 → 每轮落盘 episode.json（崩溃也不丢已完成的轮次）
            6. 终局：导出 candidate.patch（相对快照的 diff）
```

**沙箱命令的安全包装**（`EpisodeSession.run`）：
- 模型命令先过 `bash -n` 语法检查，非法直接拒绝不执行
- 注入 testbed conda 环境 PATH，`cd /testbed`，`timeout -k 5s`
- 输出经 Python drain 管道：保留头 8KB + 尾 24KB，防超大输出撑爆
- 每条命令（含系统的 trusted 命令）都记录进 `execution.json`（命令、退出码、stdout/stderr、耗时）

### 5.2 判分阶段（每条轨迹独立，fresh 沙箱）

```
evaluate_patch(inst, patch, judge_dir)
  1. 全新沙箱 + 应用候选补丁（应用失败 = 0 分 candidate_rejected）
  2. 跑官方 eval.sh 协议：
       源码导入自检 → 重置测试文件 → git apply test.patch
       → 跑测试命令（输出夹在 >>>>> Start/End Test Output 标记间）
  3. 用 swebench 官方 log_parser 解析 + Django 子测试名归一化
  4. 奖励 = F2P 通过数 / F2P 总数（0~1 连续值）
     resolved 额外要求 P2P 无回归（与官方口径一致）
  5. 健壮性降级（v4 修复）：
     - 语法/导入/收集错误、框架级启动崩溃（如 Django SystemCheckError）
       → 先跑无补丁对照确认环境健康 → 记 0 分 + failure_kind
     - 判分器残余异常 → 记 0 分 + judge_error（不让单条失败终止训练）
```

### 5.3 奖励 → 优势 → 梯度（实测数据）

```
奖励回传链（已逐段核验）：
final["reward"] → AgentLoopOutput.reward_score
  → rm_scores[最后一个有效token] → token_level_scores
  → token_level_rewards（use_kl_in_reward=False，无奖励侧KL）
  → GRPO: A_i = (r_i − mean(组内)) / (std(组内) + 1e-6)

v4 warmup 实测（零优势问题已解决）：
  step-1 django-11039 组 [0,1,1,1] → 优势 [-1.5, +0.5, +0.5, +0.5]
  critic/advantages/max = 1.5    actor/grad_norm = 0.0112（项目首次非零梯度）
```

**GRPO 关键行为**（`verl/core_algos.py`）：
- 组内奖励全相同（全 0 或全 1）→ 优势恒 0 → 该组无梯度（算法预期）
- 单例组特例：advantage = 原始分数（mean=0, std=1）
- 合成填充样本：独立 uid + mask 全零 + 奖励 0，不污染真实分组

### 5.4 更新阶段（~1.5 分钟）

| 项 | 配置 |
|---|---|
| 算法 | GRPO（`adv_estimator=grpo`，`norm_adv_by_std_in_grpo=True`） |
| 策略损失 | PPO clip（ε=0.2）+ KL loss（coef 0.001，对 ref=初始权重） |
| 参数化 | LoRA r=32 / α=64，挂 7 个 projection 模块，基座冻结 |
| 并行 | FSDP bf16 + 参数 offload；vLLM colocate 异步 rollout（TP=2） |
| 优化 | lr 1e-5，mini_batch=6，token-mean 损失聚合 |
| 同步 | 更新后 layered_summon 权重回 vLLM（下步采样用新策略） |

### 5.5 每步耗时构成（step-2 实测）

```
gen 176.8s │ old_log_prob 23.2s │ ref 18.7s │ update_actor 57.7s
checkpoint 12.7s │ update_weights 4.7s │ testing 90.1s（每10步）
合计 ≈ 294s/步；吞吐 111 tokens/s；MFU 0.46
```

---

## 6. 可观测性（每个环节都有落盘）

每条轨迹在 `traces/<run>/train/step-N/<题>/<episode_id>/` 下：

| 文件 | 内容 |
|---|---|
| `episode.json` | 逐轮 action（模型原始输出）/ executed_command / observation（≤32KB 全量）/ exit_code / reward / done；`token_alignment`（prompt_ids、response_ids、response_mask、logprobs）；**changed_files**（模型实际改动清单）；final（奖励、resolved、failure_kind） |
| `agent/execution.json` | 该沙箱全部命令（含系统命令）+ 耗时 + sandbox_id + 镜像指纹 |
| `candidate.patch` | 模型产出的最终补丁 |
| `judge/test.log` + `judge/result.json` | 判分原始日志与逐用例状态 |

**日志关键指标**（`logs/<run>/train-*.log`，每步一行）：

| 指标 | 含义 | 健康值 |
|---|---|---|
| `critic/score/max` | 原始奖励最大值 | >0（=0 说明全失败，查模型/环境） |
| `critic/advantages/max` | 组内归一化后优势 | ≠0（=0 而 score>0 查分组） |
| `actor/grad_norm` | 策略梯度范数 | >0（=0 查优势） |
| `actor/pg_clipfrac` | PPO 裁剪比例 | 小量为正常 |
| `swe_episode_complete` | 每条轨迹完成事件（JSON） | 计数 = 批次大小 |
| `swe_judge_error` | 判分降级事件 | 应为 0 或极少 |

**验收门**（`controller/report_run.py`，训练结束后自动执行）：
- `--expected 48`：轨迹数必须齐全（缺 = 有样本被丢弃）
- `--min-step 2`：达到目标步数，检查点已保存
- `--require-signal`：informative_groups ≥1（组内有奖励差异）且 nonzero_gradient_steps ≥1 —— **防止无人值守空跑零信号训练**

---

## 7. 信任与安全模型

1. **模型输出永不直接接触训练主机**：所有命令经 AGS 沙箱执行，训练 Pod 只收文本回显。
2. **trusted 双轨**：系统命令（git 快照、判分）标记 trusted 绕过语法检查；模型命令必须过 `bash -n` 且限长 12KB。
3. **补丁守卫**（`check_patch`）：拒绝改测试/配置/`.git`、二进制、重命名、>30 文件、>256KB —— 防模型作弊改测试。
4. **判分防作弊**：判分用全新沙箱 + 官方 eval.sh（重置测试文件再跑），模型看不到 gold.patch 与判分脚本。
5. **路由校验**：parquet 的 tool_name 与实例表不一致会在预检阶段拒绝启动。
6. **运行快照不可变**：每次运行用 `runs/<run-id>/kit`（含 SHA256 清单），保证可复现、可审计。

---

## 8. 当前实况（v4 warmup，修复后首次成功信号）

```
运行: recovery-14b-fullbatch-v4-warmup（2 步验收）
轨迹: 48 条训练（24/步，6 题全覆盖 × 4 采样） + 8 条评估
奖励: 5 × 1.0 + 43 × 0.0（mean 0.104，resolved_rate 0.104）
优势: step-1 advantages/max = 1.5（django-11039 组 [0,1,1,1]）
梯度: grad_norm = 0.0112 —— ★ 项目首次非零策略梯度
判分: judge_error = 0（v3 的 SystemCheckError 崩溃已修复）
检查点: step-1 / step-2 已保存（save_lora_only）
结果: 训练成功完成；Pod 报 Error 仅因质量门（2/48 条 episode
      操作数<3，属模型行为问题，非流水线故障）
```

## 9. 已知问题与下一步

| 项 | 状态 | 说明 |
|---|---|---|
| 质量门过严 | 待放宽 | "fewer than three shell operations" 对 4% 的早提交 episode 判失败；建议改为比例阈值（如 <10%） |
| sed 静默 no-op | 待修 | exit=0 但未改文件会误导模型提交空补丁（6/16 空补丁主因）；可在观察中附"未改变任何文件"提示 |
| 观察中段截断 | 待评估 | 512 token 看不到断言明细；可改为失败块聚焦（grep FAILED 上下文） |
| 50 步正式训练 | **就绪待发** | 清单 `artifacts/recovery/fullbatch-v4/swe-rl-recovery-14b-fullbatch-v4-train.json`（12h 上限，每 10 步存档+验证） |

---

## 10. 附录：关键路径速查

```
仓库 /root/swe-rl-kit/
├── sandbox/episode.py        沙箱会话 + 判分器（本次修复点）
├── sandbox/harness.py        实例加载 + 日志解析 + 奖励公式
├── verl_plugin/swe_agent_loop.py   AgentLoop（本次修复点）
├── verl_plugin/reward.py     奖励入口（只消费可信判分结果）
├── configs/grpo_l20_lora.sh  训练超参（batch=6, n=4, temp=0.7）
├── controller/report_run.py  验收门
└── deploy/*.yaml             Pod 清单

CFS /mnt/cfs/swe-rl/
├── runs/<id>/kit             每次运行的不可变代码快照 + protocol.sha256
├── verl-src/                 冻结的 verl 框架（0.10.0.dev）
├── traces/<id>/              全部轨迹（episode.json 等）
├── checkpoints/<id>/         LoRA 检查点
├── logs/<id>/                训练日志 + GPU 监控 CSV
└── eval_reports/<id>/        验收报告 summary.json
```
