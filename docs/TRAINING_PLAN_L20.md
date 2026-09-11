# Qwen3-Coder-30B-A3B LoRA-GRPO 训练方案（TKE ap-tokyo 2×L20）

> 版本：1.0 ｜ 日期：2026-09-10
> 已确认条件：东京二区 2×L20（48GB×2，同节点，固定节点）；Qwen/Qwen3-Coder-30B-A3B-Instruct；
> LoRA 训练；验收最小规模（50 step GRPO + pass@1 前后对比，1 轮闭环）；本地日志 + matplotlib。
> 沙箱侧（已就绪）：AGS ap-singapore 12 题工具（5/5 已 validated），训练数据 `data/train.parquet`（11 题）。

## 0. 方案总览

```
TKE ap-tokyo（2×L20 GPU 节点，固定）
┌─────────────────────── verl 训练 Pod（GPU×2）───────────────────────┐
│  AgentLoop(async) ── LLM 生成 bash ──┐                              │
│      │   vLLM rollout engine (TP=2, sleep 模式)                     │
│      ▼                               ▼                              │
│  E2B SDK ──── HTTPS ────▶ AGS ap-singapore 数据面                    │
│      │                      └─ 12 个 SWE 沙箱工具（1 工具=1 题）     │
│      ▼ 观察回传                                                        │
│  GRPO trainer（FSDP×2 + LoRA，KL 约束）                               │
│      │ episode (action/observation/reward/done)                     │
│      ▼                                                              │
│  CFS PVC /mnt/cfs/swe-rl/traces/  ← 验收要求的 tracing 传递通道      │
└────────────────────────────────────────────────────────────────────┘
   训练完成 → LoRA 合并 → vLLM 评估 pass@1（前后对比）
```

## 1. Sandbox 与 TKE GPU 节点的网络连接

### 1.1 链路与时延（实测/已确认事实）

| 链路 | 方式 | 时延/带宽 | 说明 |
|---|---|---|---|
| TKE tokyo → AGS ap-singapore | 公网 HTTPS（E2B 兼容协议） | RTT ~70-100ms | **AGS 无东京数据面（已探测：<tokyo-registry> 无解析/不可达）**，沙箱留在新加坡 |
| TKE tokyo → TCR ap-singapore | 公网 + imagePullSecret | 仅拉取期 | 训练镜像一次性 ~20GB，可预拉到节点 |
| TKE tokyo → HuggingFace | 公网直连 | 好 | 模型 61GB 下载到 CFS（一次性） |
| AGS → TCR | 平台内部（预热时已完成） | — | 12 工具镜像已预热 |

### 1.2 配置要点

1. **集群公网出口**：固定节点绑定 EIP 或集群配 NAT 网关（AgentLoop 出方向访问
   `ags.example.com:443`）；安全组放行 443 出站即可；
2. **沙箱侧无需任何入站配置**：SANDBOX 网络模式下，E2B 调用经平台网关进入沙箱
   envd（49983），沙箱本身不出网（测试离线，符合 SWE-bench 协议）；
3. **RTT 影响量化**：每条 bash 命令一次往返，episode ~16 步 → 每集额外 ~1.6s
   （相比沙箱执行 2-10s/步，占比 <10%），async rollout 下可忽略；
4. **tracing 传递（验收通信方式）**：AgentLoop 运行在 TKE Pod 内，episode JSONL
   直接写 CFS PVC `/mnt/cfs/swe-rl/traces/`——"SandBox→TKE 经 CFS 传递 tracing"
   由驱动侧落盘实现，无需 COS。

## 2. GPU 节点初始化与驱动/容器运行时配置

### 2.1 节点创建（控制台，一次性）

| 项 | 要求 | 说明 |
|---|---|---|
| 机型 | ap-tokyo-2，2×L20 48GB | L20 = Ada Lovelace，CC **8.9**，vLLM/PyTorch 原生支持（非 T4/V100 的 CC<8.0 禁区） |
| 驱动 | TKE 节点池勾选自动安装，**≥535**，CUDA **12.2+** | `nvidia-smi` 验证 2×L20 |
| 节点内存 | **≥240GB**（见 §3.3 显存预算：CPU offload 需容纳 61GB 权重副本） | 选高内存机型 |
| 系统盘 | ≥100GB | 训练镜像 ~20GB + 镜像缓存 |
| 容器运行时 | containerd + nvidia-container-toolkit（TKE 默认） | Pod 里 `nvidia.com/gpu: 2` |

### 2.2 节点就绪验证

```bash
kubectl get nodes -l node.kubernetes.io/instance-type=<L20机型>
# 节点上执行：
nvidia-smi   # 2×L20，驱动≥535，CUDA≥12.2
# GPU 共享/虚拟化：不需要，整卡直通（Verl Pod 独占 2 卡）
```

### 2.3 组件与存储

1. **CFS CSI**（ap-tokyo）→ StorageClass `cfs-ai` → `kubectl apply -f deploy/pvc.yaml`；
2. 训练镜像：`verlai/verl:vllm-latest` 叠加 `verl_plugin/` 后推 TCR `swe-mirror/verl-train`
   （跨区拉取用 imagePullSecret `tcr-sg`，或预 docker pull 到节点）；
3. 模型下载（一次性，节点或临时 Pod 均可）：

```bash
# CFS 挂载点
huggingface-cli download Qwen/Qwen3-Coder-30B-A3B-Instruct \
  --local-dir /mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct
```

## 3. 训练框架选型与 LoRA 训练流程

### 3.1 选型结论

- **框架：verl（FSDP backend）+ vLLM rollout + GRPO + LoRA**。
  理由：① 官方文档确认 PPO/GRPO 支持 LoRA（FSDP）；② Agent 场景必须 async rollout
  （沙箱执行慢）；③ GRPO 无 critic，2 卡显存友好；④ verl AgentLoop 原生支持自定义
  tool/sandbox 集成（我们的 Phase A 协议可直接复用）。
- **已知风险（头号）**：verl 的 LoRA × **MoE**（Qwen3-30B-A3B 是 MoE）组合官方文档
  未明确背书。缓解：训练前先跑 §3.5 冒烟链；若不兼容，降级路径见 §3.6。

### 3.2 数据准备

| 数据 | 来源 | 规格 |
|---|---|---|
| 训练/验证 prompt 池 | `data/train.parquet` | 11 题（flaky 已剔除）；RL 是 on-policy，parquet 只提供 prompt + 沙箱路由（extra_info.tool_name） |
| rollout | AgentLoop 实时生成 | 每题 n=4 条轨迹 × 最多 16 步 bash；逐步 (action, observation, reward, done) |
| reward | 沙箱 harness 判分 | `fail→pass 测试数 / F2P 总数`（harness.compute_reward，已就绪） |
| tracing 存档 | CFS | `/mnt/cfs/swe-rl/traces/{round}/{instance}/episode-*.jsonl` |

批次口径：`train_batch_size=8`（prompt 数）× `rollout.n=4` = 32 episodes/step；
50 step ≈ 400 episodes ≈ 9 个 epoch（11 题循环采样）。

### 3.3 显存预算（2×48GB=96GB，LoRA 关键数字）

| 阶段 | 每卡占用 | 说明 |
|---|---|---|
| **训练相位** | 权重分片 30.5GB + LoRA 参数/梯度/优化器 ~6GB + 激活（梯度检查点，micro_bs=1）~6GB ≈ **42-44GB** | 紧凑可行 |
| **rollout 相位** | vLLM TP=2 权重 30.5GB + KV cache（4 并发 × 12K token ≈ 5GB）≈ **36GB**（gpu_memory_utilization=0.85） | MoE 仅 3.3B 激活，生成快 |
| **相位切换** | vLLM sleep（level 2，训练期释放权重+KV）+ FSDP param_offload（rollout 期权重下放 CPU RAM） | 两者不同时驻留 GPU；节点 RAM ≥240GB 兜底 61GB 副本 |

**降级链路（OOM 时按序）**：① `max_response_length 8192→4096`；② `rollout.n 4→2`；
③ `gpu_memory_utilization 0.85→0.7`；④ 最后手段换 Qwen2.5-Coder-7B（dense，verl
最充分验证的组合）。

### 3.4 启动命令（configs/grpo_l20_lora.sh，已更新）

```bash
python3 -m verl.trainer.main \
    algorithm.adv_estimator=grpo \
    data.train_files=$VERL_DATA data.val_files=$VERL_DATA \
    data.train_batch_size=8 data.micro_batch_size_per_gpu=1 \
    data.max_prompt_length=4096 data.max_response_length=8192 \
    actor_rollout_ref.model.path=$VERL_MODEL \
    actor_rollout_ref.actor.optim.lr=1e-5 \
    actor_rollout_ref.actor.lora.rank=32 actor_rollout_ref.actor.lora.alpha=64 \
    actor_rollout_ref.actor.use_kl_loss=True actor_rollout_ref.actor.kl_loss_coef=0.001 \
    actor_rollout_ref.actor.optim.param_offload=True \
    actor_rollout_ref.rollout.n=4 actor_rollout_ref.rollout.mode=async \
    actor_rollout_ref.rollout.name=vllm \
    actor_rollout_ref.rollout.gpu_memory_utilization=0.85 \
    trainer.val_before_train=True trainer.test_freq=5 \
    trainer.max_steps=50 trainer.n_gpus_per_node=2 trainer.nnodes=1
```

关键差异（相对 3B 方案）：`lr 1e-6→1e-5`（LoRA 参数少需更大学习率）、
`n_gpus_per_node=2`、LoRA rank 32、param_offload 开启。

### 3.5 上线前冒烟链（GPU 就绪后按序，全部通过才进正式训练）

1. **vLLM 冒烟**（10min）：TP=2 加载 Qwen3-Coder-30B-A3B，生成 16 条 bash 命令，
   验证 L20 上的 MoE kernel（sm_89）；
2. **LoRA×MoE 冒烟**（30min）：verl + LoRA + GRPO 在 2×L20 跑 **2 step**（用
   `train.parquet` 子集，sandbox 换成 echo mock），验证 FSDP LoRA 对 MoE expert
   linears 的适配 + 相位切换无 OOM——**这一步是头号风险的闸门**；
3. **AgentLoop 真实冒烟**（30min）：1 题 × 1 轨迹真实走 AGS 沙箱（复用
   `agent_smoke` 协议），验证 E2B→AGS→harness 判分→rm_scores 链路在 Pod 内可用；
4. 正式训练。

### 3.6 风险与降级矩阵

| 风险 | 概率 | 降级方案 |
|---|---|---|
| verl LoRA×MoE 不兼容 | 中 | a) 关掉 LoRA 的 target_modules 限制只挂 attention（跳过 expert）；b) 换 Qwen2.5-Coder-7B dense；c) 升级 verl 最新版（MoE LoRA 是社区活跃方向） |
| 48GB 显存 OOM | 中 | §3.3 降级链路；或将 KV 量化（vLLM kv_cache_dtype=fp8，L20 支持 FP8） |
| 跨区 RTT 拖慢 rollout | 低 | async 并发下影响 <10%；必要时 episode 级并行度 8→16 |
| 11 题数据量小导致过拟合 | 低 | KL 约束已开；50 step 验收规模影响有限；后续扩题用 §批量流水线五步法 |

## 4. RL 组件与 LoRA 结合的部署架构

### 4.1 组件与数据流

```
                    ┌─────── 单 Pod（deploy/train-pod.yaml，GPU×2）───────┐
 train.parquet ──▶  │ Trainer (GRPO, step 循环)                          │
                    │   │ ① 采样 prompt 批（8 题）                         │
                    │   ▼                                                │
                    │ AgentLoop (verl.experimental.agent_loop, async)    │
                    │   ├─▶ vLLM Engine TP=2（sleep 模式）生成 bash       │
                    │   ├─▶ E2B SDK → AGS 沙箱执行 → observation 回传     │
                    │   └─▶ episode 终止（SUBMIT/16 步上限）               │
                    │        │ ② 逐步 token 对齐：action=mask1/obs=mask0  │
                    │        │    reward=f2p_pass/f2p_total → rm_scores   │
                    │        ▼                                           │
                    │   ③ FSDP Actor（LoRA rank32）GRPO 更新              │
                    │      （base 权重冻结，仅训 adapter）                 │
                    │   ④ episode JSONL → /mnt/cfs/swe-rl/traces/         │
                    └────────────────────────────────────────────────────┘
```

### 4.2 待实现组件（Phase B，GPU 就绪后）

| 组件 | 文件 | 要点 |
|---|---|---|
| AgentLoop | `verl_plugin/swe_sandbox_agent_loop.py` | 复用 Phase A 协议：全新沙箱/题（tool_name 路由）、`user="root"`、`2>&1` 合并、eval.sh 判分；token_ids 交互**绝不重新 apply_chat_template**（README 已知坑 #1）；观察进上下文前截断（坑 #2） |
| Reward | `verl_plugin/reward.py` | 直接调用 `harness.compute_reward`（沙箱在 AgentLoop 内已判分，reward 只透传 rm_scores） |
| 闭环控制器 | `controller/run_round.py` | 训练 50 step → LoRA 合并（peft merge_and_unload）→ vLLM 加载合并模型 → 11 题 × 3 次 pass@1 → 对比报告（CFS /eval_reports/） |
| SYSTEM_PROMPT | 训练/评估同源 | `data/prepare_data.py` 已内置，评估侧复用同一份（坑 #3） |

### 4.3 评估（pass@1 前后对比）

- **before**：`val_before_train=True` 自动产出（或独立跑基线评估）；
- **after**：LoRA 合并后 vLLM 评估，同一 SYSTEM_PROMPT、同一 11 题、每题 3 次
  （flaky 题已剔除不参与），输出 `compare_round0.json` + matplotlib 图。

## 5. 监控、日志与成本控制

### 5.1 监控与日志（本地方案，无外部依赖）

| 层 | 手段 |
|---|---|
| 训练指标 | verl trainer 逐步打印 `critic/rewards/mean`、`response_length`、kl、loss 到 stdout；`kubectl logs -f swe-rl-train`；同时落 CFS 日志文件 |
| **reward 曲线（验收）** | `controller/plot_reward.py`：解析 verl 指标日志 → matplotlib 出图 → `/mnt/cfs/swe-rl/eval_reports/reward_curve.png` |
| GPU 层 | Pod 内 `nvidia-smi dmon -s um` 采样脚本（利用率/显存，诊断 OOM 用）；不接云监控 |
| 沙箱层 | 每个 episode 的执行证据 sidecar（已有 `harness.Evidence`）+ CFS traces 归档 |
| 告警 | 最小化：训练 Pod `restartPolicy: Never` + kubectl 手动巡检（固定节点、验收规模，不建复杂告警） |

### 5.2 成本控制

| 项 | 措施 | 估算（验收 1 轮） |
|---|---|---|
| GPU（固定节点） | 训练 50 step（~6-10h：每 step 32 episodes，async 下 5-10min/step）+ 评估 ~2h | 2×L20 × ~12h；按量约 ¥10-15/卡/时 ≈ **¥250-360** |
| AGS 沙箱 | 验证器/rollout 均 finally `kill()`；实例 timeout 显式 1h；已预热避免冷启动超时 | 每步 32 实例 × ~3min ≈ 1.6 实例·时/step；50 step ≈ 80 实例·时（1C2Gi 规格） |
| 流量 | 训练镜像一次性 ~20GB 跨区拉取（可预拉）；tracing 走内网 CFS | 可忽略 |
| 磁盘 | CFS 500GB PVC；traces ~400 episodes × ~50KB ≈ 20MB | 可忽略 |

### 5.3 训完即停清单（固定节点也不空烧）

1. 训练 Pod `restartPolicy: Never` 自然退出；
2. `controller/run_round.py` 完成评估后输出报告并退出；
3. 人工确认产物齐备（reward 曲线 / compare_round0 / traces）后，节点池缩容或关机
   （后续扩题/再训再拉起，镜像与 CFS 数据持久）。

## 6. 执行清单（GPU 节点就绪后，按序）

```
① §2 节点创建 + nvidia-smi 验证 + CFS CSI/PVC
② 模型下载到 CFS（~61GB）+ 训练镜像构建推 TCR + Secret（tcr-sg / ags-credentials）
③ §3.5 冒烟链三步（vLLM → LoRA×MoE 2step → AgentLoop 真实 1 题）
④ kubectl apply -f deploy/train-pod.yaml（含 configs/grpo_l20_lora.sh）
⑤ 50 step 训练（kubectl logs 跟踪；reward 曲线脚本并行挂载 CFS）
⑥ LoRA 合并 → pass@1 评估 → compare_round0 报告 + reward_curve.png（验收产物）
```
