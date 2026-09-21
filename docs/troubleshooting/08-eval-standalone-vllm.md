# 08 · 评估阶段 OOM 与独立 vLLM 评估架构

> base vs LoRA 对照评估中，verl `val_before_train` 路径**连续 5 次**在同一位置 OOM
> （`update_weights`，差 192MB）；配置微调全部无效，最终以「独立 vLLM driver」
> 架构级修复：**零 OOM，40 题 16 分钟**，并连带解决 LoRA 加载与上下文预算两个障碍。

---

## 1. 现象：同一位置连续 5 次 OOM

### 1.1 报错

```
torch.OutOfMemoryError: CUDA out of memory. Tried to allocate 192.00 MiB.
GPU 0 has a total capacity of 44.39 GiB of which 127.81 MiB is free.
...
this process has 28.59 GiB in use
Process 9965 has 15.61 GiB in use
```

调用栈定位到**初始权重同步**（而非训练步或生成）：

```
verl/checkpoint_engine/base.py:514  update_weights
  → ray.get(self.actor_wg.update_weights(...))
  → verl/workers/engine_workers.py:785  torch.OutOfMemoryError
ray::WorkerDict.actor_rollout_ref_update_weights()
```

### 1.2 显存账（44.39 GiB 单卡）

| 占用方 | 大小 | 说明 |
|---|---|---|
| actor（FSDP，含 gather 缓冲） | 28.59 GiB | base 权重分片 15.3 + 激活/缓冲 ~13.3 |
| vLLM TP worker | 15.61 GiB | 权重唤醒（`wake_up(tags=['weights'])`） |
| **合计** | **44.2 / 44.39 GiB** | 差 **192 MB** 即触发 OOM |

### 1.3 5 次尝试（全部失败）

| # | 变量 | 结果 |
|---|---|---|
| 1-3 | 复刻训练编排（`total=1`）、分批 val | 同位置 OOM |
| 4 | `total=1` 最小配置 | OOM（free 127.81 MiB） |
| 5 | 关 KL（`use_kl_loss=False`）+ `util=0.42` + `max_response=4096` + `batch=4` | OOM（free 159.81 MiB） |

**关键判据**：第 5 次把能省的都省了（response 减半、KL 关闭、util 下调），free 仅从
127.81 → 159.81 MiB——**差距是结构性的，不是配置能补的**。

---

## 2. 根因：共卡架构在 val-only 路径的分配模式差异

**为什么训练跑得通（50 步 + val）、评估必挂？**

两条路径走的是同一个 `update_weights`，但**调用时机与分配历史不同**：

- **训练路径**：`rollout → 训练 → sleep/wake` 循环反复执行，PyTorch 缓存分配器已被
  「训练过」——各 size bucket 有复用块，权重唤醒复用既有块；
- **评估路径**：`val_before_train` 是**初始化后的第一个重操作**，此时分配器尚未形成
  可复用的 size bucket；actor 的 28.59 GiB 与 vLLM 唤醒的 15.61 GiB 把显存切成碎片，
  192 MiB 的连续块无从而来。

**结论**：这不是「少开几个并发」能解的——**是共卡架构（FSDP actor + ref + vLLM colocate）
在显存 44GB 上的结构性上限**。评估只需要「推理 + 判分」，本就不需要 actor/FSDP 常驻。

---

## 3. 修复：独立 vLLM driver（架构级）

### 3.1 设计

```
┌─────────────── 评估 Pod（4×L20，192GB）───────────────┐
│  vLLM（TP=4，util=0.85）—— 独占显存，无 actor/FSDP     │
│    权重 15.3GB/卡 + KV ~20GB/卡 → 余量健康            │
│           ▲                                            │
│           │ 批量生成（每轮全部活跃题一次前向）          │
│  eval_driver.py（轻量，无 torch 训练栈）                │
│    ├─ 沙箱：EpisodeSession（apply_test_patch=True）    │
│    ├─ 判分：evaluate_patch（全新沙箱，与训练同源）      │
│    └─ 协议：parse_action / bounded_observation         │
└────────────────────────────────────────────────────────┘
```

**复用而非重写**（保证与训练公平、轨迹同构）：
`EpisodeSession`（沙箱会话）、`evaluate_patch`（判分）、`parse_action` /
`bounded_observation`（协议）、`load_instances`（实例元数据）。

**执行模型：同步轮次推进**
每轮对所有活跃题一次性 `llm.generate`（vLLM 满批处理），随后线程池并发执行沙箱命令。
跨题互不干扰，语义与训练 AgentLoop 的逐轮推进一致。

### 3.2 结果

| 指标 | verl val 路径 | 独立 vLLM driver |
|---|---|---|
| OOM | 5/5 次 | **0 次** |
| 40 题耗时 | — | **~16 分钟**（12 轮生成 92s/轮 + 判分并发） |
| 显存 | 44.2/44.39 GiB 贴线 | 每卡约 30GB（余量 >10GB） |

---

## 4. 连带障碍（同一次改造中解决）

### 4.1 vLLM 不支持 Qwen3-MoE 的 unpacked k_proj/o_proj LoRA

**现象**：
```
ValueError: model.layers.0.self_attn.k_proj.lora_A.default.weight is unsupported LoRA weight
```
**根因**：训练 adapter 为 attention-only 全模块（`q/k/v/o`，r=32, alpha=64）；vLLM 对
Qwen 系按 packed `qkv_proj` 匹配 LoRA，unpacked 的 `k_proj` 不在其支持列表。
**修复**：**离线合并 LoRA 到 base**（`W + (alpha/r)·B@A`），得到普通完整模型，
vLLM 以常规路径加载——彻底绕开 LoRA 支持矩阵。
**沉淀**：跨引擎搬运 LoRA 时，**先确认目标引擎的 target_modules 支持面**；
合并是最稳的兼容层（本例 192 个模块 / 18867 张量，61.1GB / 16 分片）。

### 4.2 镜像 transformers 5.5.3 移除 HybridCache（放弃 peft 合并路径）

**现象**：
```
ImportError: cannot import name 'HybridCache' from 'transformers'
（镜像自报版本：transformers 5.5.3 | peft 0.19.1 | accelerate 1.12.0）
```
**根因**：镜像内 transformers 为 v5 重构版，4.x 的 `HybridCache` API 已移除，
Qwen3-MoE 的高层建模路径不可靠；`pip install peft/accelerate` 亦会破坏镜像环境一致性。
**修复**：改用**纯 torch + safetensors 的权重级合并**（`merge_lora_native.py`）——
逐分片流式处理（峰值内存 ~2×分片），**不导入 transformers**，纯 CPU（零 GPU 计费），
15 分钟完成 61.1GB。

### 4.3 driver 缺上下文预算管理（16384 超限）

**现象**：
```
VLLMValidationError: maximum context length is 16384 tokens.
However ... your prompt contains at least 16385 input tokens
```
**根因**：训练 AgentLoop 由 token 预算（`response_length`）驱动终止；driver 初版只有
`max_steps` 步数上限，长输出累积超限后 vLLM 直接拒绝请求并终止进程。
**修复**：每轮生成前计算各题 prompt token 数，`> 16384 - 512` 即终止该题（强制提交）；
并令本轮 `max_tokens = min(action_tokens, 16384 - max(prompt_tokens) - 8)`。
**沉淀**：**跨题合批生成时，上下文预算必须逐题显式管理**——步数上限不等于 token 上限。

---

## 5. 沉淀（工程原则）

1. **共卡架构的显存极限不是调参问题**：当「能省的都省了」仍差 <200MB 时，说明需求
   超过结构上限，应改架构而非继续找参数。
2. **评估与训练的资源需求分离**：推理 + 判分不需要训练栈常驻；独立 driver 把单卡
   需求从「28.6 + 15.6GB」降到「~15.3GB 权重 + KV」，同时更快（批处理 + 无同步开销）。
3. **复用判分/沙箱组件**是公平性的前提：driver 与训练共用 `EpisodeSession` /
   `evaluate_patch`，避免"两套判分"引入的系统性偏差。
4. **兼容性矩阵要先验证**：vLLM↔LoRA target_modules、transformers↔模型架构、
   vLLM↔上下文长度，三者都必须在跑批前用小样本验证（冒烟 2 题的成本 << 40 题重跑）。
5. **失败也是产物**：5 次 OOM 的显存账（28.59 + 15.61 = 44.2/44.39）是"为何必须
   扩卡/改架构"的直接证据，已并入 H20 资源申请材料。
