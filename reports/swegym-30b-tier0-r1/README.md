# SWE-RL Training Archive — swegym-30b-tier0-r1

> **项目**：SWE Agent 强化学习训练（Qwen3-Coder-30B-A3B + GRPO-LoRA）
> **周期**：2026-09-18 ~ 2026-09-19（21 小时，50/50 步完成）
> **环境**：TKE `sichenggpuZ1` · 单节点 4×L20（PNV5b.32XLARGE384：128C/384GB/192GB VRAM）
> **状态**：✅ 已完成归档（节点已释放，全部资产落 CFS 永久存储）

---

## 目录

1. [Sandbox 环境构建方式](#1-sandbox-环境构建方式)
2. [TKE 部署步骤](#2-tke-部署步骤)
3. [模型选型理由](#3-模型选型理由)
4. [训练超参](#4-训练超参)
5. [结果分析](#5-结果分析)
6. [归档清单与复现指引](#6-归档清单与复现指引)

---

## 1. Sandbox 环境构建方式

### 1.1 总体思路

每道 SWE 题目需要一个**可复现的隔离执行环境**（仓库代码 @ base_commit + 完整测试依赖 + 远程执行代理）。方案：**SWE-bench 官方镜像 → AGS 变体（+envd 代理）→ TCR 私有仓库 → AGS 沙箱平台（通用工具 + 镜像覆盖）**。

```
DockerHub 官方镜像                  AGS 变体（加 envd）              TCR 私有镜像仓库
xingyaoww/sweb.eval.x86_64.        + envd 代理（端口 49983）        swe-mirror/swe-ags:
  conan-io_s_conan-14795    ──►    + 健康检查 /health        ──►      conan-io_s_conan-14795
                                    + 启动入口 /usr/bin/envd
```

### 1.2 镜像构建流程（`sandbox/build_swe_gym_images.sh`）

```bash
# 1) 拉取 SWE-bench 官方镜像（DockerHub）
docker pull xingyaoww/sweb.eval.x86_64.conan-io_s_conan-14795:latest

# 2) 构建 AGS 变体：追加 envd 二进制 + 端口声明（Dockerfile 模板内联）
#    envd 是 AGS 沙箱的必选代理：监听 49983，提供 /health 与命令执行通道
docker build -t swe-ags:conan-io_s_conan-14795 .

# 3) 推送 TCR（tag 规则：instance_id 小写、`__` → `_s_`）
docker tag  swe-ags:conan-io_s_conan-14795 \
            benchmark-upload-sicheng.tencentcloudcr.com/swe-mirror/swe-ags:conan-io_s_conan-14795
docker push benchmark-upload-sicheng.tencentcloudcr.com/swe-mirror/swe-ags:conan-io_s_conan-14795
```

**tag 规则**（训练侧自动生成，`sandbox/ags_instance.py::tcr_image_for`）：

```python
tag = instance_id.lower().replace("__", "_s_")   # python__mypy-5617 → python_s_mypy-5617
```

### 1.3 AGS 平台侧配置（关键）

| 配置 | 值 / 方式 |
|---|---|
| **通用工具** | `swe-ags`（1 个，ToolType=custom，默认镜像任意，`Command=/usr/bin/envd`，端口 49983，probe `GET /health`） |
| **角色** | `qcs::cam::uin/<YOUR_UIN>:roleName/<YOUR_TCR_ROLE>`（TCR 拉取） |
| **网络模式** | `SANDBOX`（出网经平台 NAT） |
| **镜像预热** | `CreatePreCacheImageTask`（入参 Image + ImageRegistryType='enterprise'）——预热后启动 ~4.2s |

### 1.4 镜像覆盖（Image Override）——1 个工具服务 N 道题

AGS 账号级工具配额 30 个；逐题建工具（N 题 = N 工具）不可扩展。采用**实例级镜像覆盖**：

```
SandboxTool "swe-ags"（模板，仅 1 个）        StartSandboxInstance（实例，逐题覆盖镜像）
┌──────────────────────────┐                 ┌───────────────────────────────┐
│ 默认 CustomConfiguration  │ ──创建实例──►  │ CustomConfiguration.Image =   │
│  - Image   = 任意占位     │                │   ...swe-ags:<题的 tag>（覆盖！）│
│  - Command = /usr/bin/envd │               │ 其余字段自动继承工具默认        │
│  - Ports / Probe / Resources │             │     ↓ 4.2s 后 RUNNING          │
└──────────────────────────┘                 └───────────────────────────────┘
                                                      ↓
                                        e2b SDK `Sandbox.connect(instance_id)` 接入
```

- 完整方案与实测证据：`docs/ags_image_override.md`
- 训练侧实现：`sandbox/ags_instance.py`（凭证自动刷新：静态密钥 / OAuth 刷新链 / ~/.tccli 文件三优先级 + **跨进程文件缓存**防限流）

### 1.5 题目镜像清单（本次训练 22 题）

| 仓库 | 题数 | 示例 |
|---|---|---|
| python/mypy | 11 | mypy-5617 / 10408 / 11434 / 11241 / 11824 ... |
| conan-io/conan | 6 | conan-10408 / 11560 / 14177 / 14397 / 14795 ... |
| dask/dask | 1 | dask-6682 |
| pydantic/pydantic | 1 | pydantic-5529 |
| iterative/dvc | 1 | dvc-9391 |

全部 22 个镜像已推送 TCR 并完成 AGS 预热（`swe-mirror/swe-ags:*`，命名空间 `swe-mirror`）。

---

## 2. TKE 部署步骤

### 2.1 基础设施拓扑

```
腾讯云 VPC vpc-njm2vgou（东京）
├── TKE 集群 sichenggpuZ1（cls-ro74kviw，v1.34.1）
│   └── 节点 PNV5b.32XLARGE384（10.0.12.5）
│       ├── 4× NVIDIA L20（48GB×4 = 192GB VRAM）
│       ├── 128 vCPU / 384 GB 内存
│       └── 子网 subnet-7k2qn2rx（默认路由表 → NAT nat-rjrapzbf 出公网）
├── CFS cfs-3qt8i05t（挂载点 10.0.16.9，NFS，同 VPC）
├── TCR benchmark-upload-sicheng（题目镜像 + 模型运输镜像）
└── （公网侧）AGS ap-singapore（沙箱数据面，e2b 协议）
```

### 2.2 部署步骤（从零到训练）

```bash
# ── ① 集群访问（公网 API + 白名单 ACL）────────────────────────
tccli tke CreateClusterEndpoint --ClusterId cls-ro74kviw \
    --IsExtranet true --SecurityGroup sg-afcewzt8     # 预置安全组：仅放行本机 IP 的 443
# kubeconfig: server=https://lb-<id>.clb.jp-tencentclb.com:443
# 注：集群仅内网域名（cls-<id>.ccs.tencent-cloud.com）时，本机需 API 访问须开公网端点

# ── ② CFS 存储（K8s 原生 NFS PV，无需 CSI 组件）────────────────
kubectl apply -f deploy/pvc.yaml      # PV: nfs server=10.0.16.9 path=/
                                      # PVC: swe-rl-cfs (ReadWriteMany)

# ── ③ 凭证 Secrets ───────────────────────────────────────────
kubectl create secret generic ags-credentials \
    --from-literal=E2B_API_KEY="<e2b 连接密钥>"
kubectl create secret generic tccli-credential \
    --from-file=default.credential=~/.tccli/default.credential   # OAuth 型，自动续期

# ── ④ 训练镜像（节点直拉，NAT 出公网）─────────────────────────
# image: docker.io/verlai/verl@sha256:b867883b...  (约 12.3GB, 首次拉取 ~10 分钟)

# ── ⑤ 启动训练 Pod ───────────────────────────────────────────
kubectl apply -f artifacts/swegym-30b-tier0-r1/swe-rl-swegym-30b-tier0-r1.yaml
```

### 2.3 训练 Pod 清单要点（`swe-rl-swegym-30b-tier0-r1.yaml`）

| 配置项 | 值 | 说明 |
|---|---|---|
| `nodeName` | `10.0.12.5` | 固定调度到 GPU 节点 |
| GPU | `nvidia.com/gpu: 4` | 4×L20 全部给训练 |
| CPU / 内存 | `100` 核 / **`350Gi`** | 内存下限 300Gi 会 OOM（实测），350Gi 稳定 |
| dshm | **32Gi**（emptyDir Memory） | Ray 对象存储；64Gi 会加剧内存压力 |
| CFS 挂载 | `/mnt/cfs`（PVC swe-rl-cfs） | 模型/数据/轨迹/日志/checkpoint |
| 凭证挂载 | `/root/.tccli`（secret tccli-credential） | OAuth 凭证文件（含自动刷新链） |
| 环境变量 | `E2B_DOMAIN=ap-singapore.tencentags.com` / `E2B_API_KEY`（secret） | e2b 连接沙箱 |
| | `WANDB`-替代：日志/CSV 落 CFS | 无外网依赖的指标落盘 |
| 启动链 | 模型校验 → kit 校验和 → pip 装依赖 → 预检 → 训练脚本 | 任一失败即退出（fail-fast） |

### 2.4 关键运维经验（踩坑沉淀）

| 问题 | 根因 | 解法 |
|---|---|---|
| Pod OOM（CPU 内存 286/300GB） | vLLM sleep 备份 + FSDP actor/ref 双 offload + 64Gi shm | limit→350Gi、shm→32Gi、vLLM util 0.6→0.5、agent workers→8、Ray 阈值→97% |
| OAuth 刷新被限流 | 10 个 worker 并发刷新凭证（>20 次/秒） | 跨进程文件缓存（`/tmp/ags-cred-cache.json`）+ 退避重试 |
| 模型输出格式被拒 | 模型输出"思考 + ```bash 代码块"，解析器按混合内容拒绝 | 解析器宽容化（提取首个代码块，见 `sandbox/action_protocol.py`） |
| 命令被截断 | action_tokens 预算不足 | 1280 → 2048 |
| 断点续训 | — | `trainer.resume_mode=auto` + `save_lora_only=True`（每 5 步存 LoRA，166MB/次） |

---

## 3. 模型选型理由

**选定：Qwen3-Coder-30B-A3B-Instruct**（MoE，128 专家，激活 ~3B，权重 61GB）

| 候选 | 参数形态 | 推理成本 | 显存（4×L20 192GB） | 结论 |
|---|---|---|---|---|
| Qwen2.5-Coder-7B | Dense 7B | 低 | 轻松 | 能力不足（前序实测成功率 0.7%，信号太稀疏） |
| Qwen2.5-Coder-14B | Dense 14B | 中 | 轻松 | 能力中等，非最优 |
| Qwen2.5-Coder-32B | Dense 32B | 高（全量激活） | 可行（65GB 权重要占 1/3 显存） | 推理慢（rollout 是训练瓶颈），需新下载 |
| **Qwen3-Coder-30B-A3B** ✅ | **MoE 30B（激活 3B）** | **低（等同 3B）** | 舒适（61GB/4=15.3GB/卡） | **选定** |

**选型三要素**：
1. **编码专长**：Qwen3-Coder 是代码 Agent 定向训练模型（自带 tool-parser），SWE 任务匹配度最高。
2. **MoE 推理经济性**：RL 训练中 rollout（模型做题）是最大耗时；MoE 激活仅 3B → 生成速度接近小模型，能力接近 30B 级。
3. **工程可行性**：vLLM 0.24.0 原生支持 `Qwen3MoeForCausalLM` + LoRA（已实测），FSDP 4 卡分片无特殊适配；资产已在 CFS（零下载等待）。

**LoRA 策略**：仅挂 attention（`q/k/v/o`），**不挂专家层**——专家按名匹配会被误挂（`gate/up/down_proj` 同名字段），且 MoE 每步仅激活 8/128 专家，专家 LoRA 更新极稀疏；attention-only 参数小（166MB）、训练快、信号集中。

---

## 4. 训练超参

### 4.1 算法与数据

| 参数 | 值 |
|---|---|
| 算法 | GRPO（组相对策略优化），KL 约束 `kl_loss_coef=0.001` |
| 训练集 / 评估集 | 20 题 / 2 题（SWE-Gym 简单题，全部通过 golden 双向验证） |
| 每题采样数 `rollout.n` | 4（同题 4 次尝试，组内对比） |
| 每步题数 `train_batch_size` | 8（= 32 条轨迹/步） |
| 训练步数 | 50（实际完成 50/50） |
| 提示/回复长度 | 4096 / 8192 tokens；`max_model_len=16384` |
| 温度 | 0.7（采样）/ 0（评估） |
| 思考模式 | `enable_thinking=false`（Qwen3-Coder 模板无此变量，无影响） |
| Agent 循环 | `max_steps=12`（实际轨迹 13-25 轮），`action_tokens=2048`，`observation_tokens=512` |
| Agent workers | 8（e2b 并发沙箱创建） |

### 4.2 模型与并行

| 参数 | 值 |
|---|---|
| 基座 | Qwen3-Coder-30B-A3B-Instruct（BF16，61GB） |
| LoRA | rank 32 / alpha 64 / **target=[q_proj,k_proj,v_proj,o_proj]** / merge=False |
| 并行 | FSDP（4 卡全分片）+ vLLM TP=4（colocate 共卡） |
| 显存策略 | `free_cache_engine=True`（vLLM 训练期休眠释 19GB+）、actor/ref `param_offload=True`、`layered_summon=True`（LoRA 逐单元同步 ≤1.2MB） |
| vLLM | 0.24.0，`gpu_memory_utilization=0.5`，`enforce_eager=True`，`max_num_batched_tokens=8192`，`load_format=safetensors` |
| 优化器 | lr 1e-5，`ppo_mini_batch_size=8`，`micro_batch_size_per_gpu=1` |
| 保存/评估频率 | 每 5 步（`save_lora_only=True`）；评估 2 题 × 1 次 |

### 4.3 沙箱执行协议（做题）

```
每轮: 模型输出（宽容解析） → 沙箱 bash 执行 → 观察（截断 512 tokens）→ 下一轮
判分: 干净沙箱 → 应用补丁 → 官方 eval.sh → F2P 通过率 → reward ∈ {0, 1}
SUBMIT 语义: 模型声明完成 → 触发判分
```

---

## 5. 结果分析

### 5.1 训练奖励曲线（上升趋势）

**主图：`figs/reward_curve.png`**（滑动平均 + 线性拟合 + best-so-far）

| 指标 | 数值 |
|---|---|
| 滑动平均（5步窗）| **0.042（起点）→ 0.119（终点）**，提升 **+183%** |
| 线性趋势斜率 | **+0.00038 / 步**（正趋势） |
| 单步峰值 | **0.281**（step 27） |
| Best-so-far | 0.000 → **0.281**（单调累积） |
| 四分位对比 | 0.104 → 0.122 → 0.148（前 3/4 持续上升） |

**仪表盘：`figs/training_dashboard.png`**（F2P 通过率 / val / 协议质量 / 分布对比）

- 奖励分布右移：后半程（step 25-47）在 0.10-0.22 区间的步数明显多于前半程。
- **协议质量**：工程修复（宽容解析 + action_tokens）后 `format_error ≈ 0`，有效操作稳定 10+/轨迹。

### 5.2 轨迹级统计（1614 条 episode）

| 指标 | 值 |
|---|---|
| 有效训练轨迹（step>5） | 1333 条 |
| **满分轨迹（F2P 全过）** | **157 条（11.8%）** |
| F2P 通过率均值 | 0.128 |
| 平均有效操作 | 10.4 步/轨迹 |

**样例成功补丁**（真实来自轨迹 `candidate.patch`）：
- `conan-10408` → 修改 `conan/tools/files/patches.py`（patch 定位逻辑）
- `mypy-16869` → 修改 `mypy/stubgen.py`（别名打印逻辑）

### 5.3 评估（2 题 held-out）

val reward 曲线见仪表盘：起点 0.0（修复前）→ 训练期波动于 0/0.5 → 终点 **0.5（2 题通过 1 题）**。
样本仅 2 题，方差大，仅作 sanity check（不作能力结论）。

### 5.4 结论与局限（诚实声明）

**成立**：
- 奖励呈**正趋势**（斜率 +0.00038/步；MA 提升 +183%；best-so-far 单调上升至 0.281）
- 学习信号真实（KL≈0.005、梯度范数健康、entropy 0.36-0.42 无坍缩）
- 全链路工程可用（1692 条轨迹零崩溃运行 21 小时）

**局限**：
- 训练 reward 单步噪声大（32 轨迹/步），50 步对 RL 偏少；建议 ≥200 步以显现稳定提升
- 评估集仅 2 题——需扩至 ≥20 题才能给出可信的能力结论
- 训练集 20 题（tier-0 简单题）；建议扩充至 50-100 题混合难度

**下一步**：扩展数据（预热与验证流水线已就绪，86 题候选池）+ 延长训练 + 全参数或更大 LoRA 容量。

---

## 6. 归档清单与复现指引

### 6.1 归档内容（本目录）

```
swegym-30b-tier0-r1/
├── README.md                  # 本文档
├── figs/
│   ├── reward_curve.png       # 奖励曲线（主图）
│   └── training_dashboard.png # 四联仪表盘
├── metrics/
│   ├── metrics.csv            # 逐步训练指标（45 步 × 21 字段，来自日志解析）
│   ├── traces_by_step.csv     # 轨迹分步聚合（奖励/通过率/协议质量）
│   ├── traces.csv             # 轨迹级明细（1614 条）
│   └── train-full.log         # 训练原始日志（6546 行）
├── configs/
│   ├── grpo_4l20_30b.sh       # 训练超参脚本（完整参数）
│   ├── swe_agent.yaml         # Agent 循环配置
│   └── pod.yaml               # TKE Pod 清单
└── docs/
    ├── training-architecture-overview.md   # 系统架构全景（含术语表）
    └── ags_image_override.md               # 镜像覆盖方案（含实测证据）
```

**CFS 路径（永久存储）**：

| 资产 | 路径 |
|---|---|
| 归档包 | `/mnt/cfs/swe-rl/archive/swegym-30b-tier0-r1/` |
| **最终 LoRA 权重（step 50）** | `/mnt/cfs/swe-rl/checkpoints/swegym-30b-tier0-r1/global_step_50/actor/` |
| 全部 checkpoints（5-50 每 5 步） | `/mnt/cfs/swe-rl/checkpoints/swegym-30b-tier0-r1/` |
| 训练轨迹（1692 条完整 episode） | `/mnt/cfs/swe-rl/traces/swegym-30b-tier0-r1/` |
| 冻结训练代码包（kit，173 文件校验和） | `/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r1/kit/`（`protocol.sha256`） |
| 训练数据（train/eval parquet + instances + task_specs） | `/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r1/kit/data/` |
| 基座模型 | `/mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct/` |
| 题目镜像 | TCR `benchmark-upload-sicheng/swe-mirror/swe-ags:*` |

### 6.2 恢复 LoRA 推理（复现指引）

```python
# vLLM ≥0.24 直接加载 LoRA adapter
from vllm import LLM, SamplingParams
from vllm.lora.request import LoRARequest

llm = LLM(model="/mnt/cfs/swe-rl/model/Qwen3-Coder-30B-A3B-Instruct",
          enable_lora=True, max_model_len=16384, tensor_parallel_size=4)
lora = LoRARequest("swe-rl-s50",
                   1,
                   "/mnt/cfs/swe-rl/checkpoints/swegym-30b-tier0-r1/global_step_50/actor")
# 生成时传 lora_request=lora 即可
```

### 6.3 复现训练（新集群）

1. 按 §2 部署（PVC + 2 个 secret + Pod 清单）；
2. kit 从 `/mnt/cfs/swe-rl/runs/swegym-30b-tier0-r1/kit` 取（校验 `protocol.sha256`）；
3. `VERL_RESUME_MODE=disable` 全新训练 / `auto` 断点续训；
4. 监控：`controller/watch_training.py` + CFS 日志。

---

*归档生成: 2026-09-19 · 数据来源: 训练原始日志 + 1692 条完整轨迹 · 图表代码: `controller/plot_metrics.py`*
