# 04 · 训练引擎与资源问题（verl / FSDP / vLLM）

> 显存 OOM 完整链条、CPU 内存 OOM、权重同步、断点续训、依赖缺失——训练引擎层全部坑位。

---

## 1. 显存 OOM 完整链条（单卡 7B/9B 时代，44GB L20）

### 1.1 KV cache 不足（vLLM 起不来）

**现象**：
```
ValueError: No available memory for the cache blocks.
GPU KV cache needs 8.1 GiB but only 2.89 GiB available
```
**根因**：模型原生上下文 262144（26 万 token）→ vLLM 按 `max_model_len` 预留 KV cache；0.45 显存利用率下不够。
**修复**：`max_model_len=16384`（Agent 单轨迹实际只需 ~12k）——KV 需求瞬间降到 <1GB。
**沉淀**：**永远为 RL 场景显式收窄上下文**（原生 26 万 ≠ 需要 26 万）；`max_model_len` 是第一止损点。

### 1.2 权重同步 OOM（训练→vLLM 搬运）

**现象**：`update_weights` 阶段 `CUDA out of memory`——vLLM（18.4GB）+ FSDP 全量参数上 GPU（18GB）+ 杂项 ≈ 44.4GB 贴线。
**根因**：训练期 vLLM 不释放显存（`free_cache_engine` 默认未启用）；且 LoRA 模式 `update_weights` 需把 base 权重搬上 GPU 做合并。
**修复（两步，缺一不可）**：
1. `actor_rollout_ref.rollout.free_cache_engine=True`——vLLM 训练期休眠释放 ~19GB；
2. 唤醒后**逐单元导出**（`layered_summon=True` + `verl_plugin/adapter_export.py`）——LoRA 参数按单元搬（每次 ≤1.2MB）而不是全量 19GB。

**沉淀**：colocate 模式的显存等式 = vLLM 活跃占用 + 训练态占用 + **搬迁瞬时占用**——第三项最容易被忽略。

### 1.3 `free_cache_engine` 后的"顺序矛盾"

**现象**：启用休眠后仍 OOM：日志显示 vLLM 已释放 19GB，但 `update_weights` 又先 `resume`（唤醒权重接收方）→ FSDP 全量上 GPU → 再次挤爆。
**根因**：verl 的搬运流程要求"接收方醒着"，与"训练期卸载"存在时序冲突；解法在于**搬运粒度**而非唤醒时机。
**修复**：确认 `layered_summon` 路径生效（`base_sync_done=True` 时走逐层收集）——单次搬运量 19GB → 1.2MB，矛盾化解。
**沉淀**：遇到"资源时序矛盾"，先问"能不能把单位改小"（全量→逐层→逐单元），往往比调度优化更直接。

---

## 2. CPU 内存 OOM（30B-MoE 4 卡时代，Ray 杀 worker）⚠️

**现象**：
```
ray.exceptions.OutOfMemoryError: 7 worker(s) were killed due to the node running low on memory.
Memory on the node was 286.52GB / 300.00GB (0.955); OOM kill reason: exceeded threshold of 95%
```
训练跑至 step 5 时被 Ray 内存监控杀掉 7 个 worker（vLLMHttpServer + AgentLoopWorker），任务以 Error 退出。

**根因（内存账单）**：

| 占用方 | 估算 |
|---|---|
| vLLM sleep 权重备份（搬 CPU） | ~100GB |
| FSDP actor `param_offload` | 61GB |
| FSDP ref `param_offload` | 61GB |
| Ray 共享内存（dshm 64Gi 全占） | 62GB |
| 引擎/进程/数据 | ~20GB |
| **合计** | **~286GB → 撞 95% 阈值（300Gi 上限）** |

**修复（五项组合拳）**：

| 项 | 前 → 后 | 收益 |
|---|---|---|
| Pod 内存 limit | 300Gi → **350Gi** | +50GB 空间 |
| dshm（Ray object store） | 64Gi → **32Gi** | -32GB 需求 |
| vLLM `gpu_memory_utilization` | 0.6 → **0.5** | 备份体积缩小 |
| AgentLoop workers | 10 → **8** | 降并发内存 |
| Ray 阈值 `RAY_memory_usage_threshold` | 0.95 → **0.97** | +7GB 缓冲 |

修复后：内存稳定在 **~289GB / 350Gi**（余量 51GB），跑完剩余 45 步零 OOM。

**沉淀（铁律）**：
- **30B 级模型单机训练的 CPU 内存 ≈ 3× 模型大小**（3 份副本：vLLM 备份 + actor + ref）+ 共享内存；
- 估算公式：`内存 ≥ 3×权重 + shm + 50GB`；
- Ray 的 OOM killer 会**同时杀多个 worker**（不是温和的单杀）——`RAY_memory_usage_threshold` 是最后防线，但治本是降需求。

---

## 3. 断点续训（让中断从灾难变插曲）

**现象**：OOM 后从头训练 = 浪费 5 步 GPU 时间（~1.5 小时）。

**修复**：
1. 存档侧：`+actor_rollout_ref.actor.checkpoint.save_lora_only=True` + `save_freq=5`——每 5 步存 **LoRA-only**（166MB，而非 61GB 全量）；
2. 恢复侧：`trainer.resume_mode=auto`——自动发现 `latest_checkpointed_iteration.txt` 并从该步继续；
3. 配套：resume 时跳过重复评估（`val_before_train=False`）。

验证（日志确认四件套全部恢复）：
```
Loaded LoRA-only checkpoint (384 keys)
Loaded optimizer / lr_scheduler / rng  from global_step_5/
```

**沉淀**：**小存档（LoRA-only）+ 自动恢复**是单机长跑训练的标准保险；存频率权衡：5 步 ≈ 1.5 小时损失上限。

---

## 4. 多模态"意外"——Qwen3.5-9B 加载失败

**现象**：
```
ValueError: ... requires an image processor (preprocessor_config.json not found)
```
**根因**：Qwen3.5-9B 是**原生多模态**（`Qwen3_5ForConditionalGeneration` + vision_config）——transformers 按多模态加载，但模型目录缺 `preprocessor_config.json` / `video_preprocessor_config.json`（下载时未包含）。
**修复**：从 HuggingFace 补齐文件 + 更新完整性清单；或换纯文本模型。
**沉淀**：**选模型先读 `config.json`**（`architectures`、是否有 `vision_config`）——名字像语言模型的可能是多模态混合体，配套文件与 vLLM 支持度是隐藏成本。

---

## 5. 训练镜像依赖缺失

### 5.1 `ModuleNotFoundError: No module named 'tencentcloud'`
**现象**：切到镜像覆盖模式后，训练启动即报错（AgentLoop worker 全挂，`Received an empty list as keys` 级联）。
**根因**：镜像覆盖模式需要调用腾讯云 API（`StartSandboxInstance`），而训练镜像里没有云 SDK（旧模式走纯 e2b 协议不需要）。
**修复**：启动脚本 pip 追加 `'tencentcloud-sdk-python-ags'`（分服务小包，比全量 SDK 轻）。
**沉淀**：**切换接入方式时同步检查依赖清单**——协议变（e2b-only → API+e2b）依赖就变。

### 5.2 依赖清单（历次累积）
`accelerate==1.15.0` · `e2b==2.49.0` · `unidiff==0.7.5` · `swebench==5.0.2` · `tencentcloud-sdk-python-ags`

---

## 6. Hydra 参数前缀踩坑

**现象**：`Could not override 'actor_rollout_ref.ref.fsdp_config.param_offload'. To append use +...` 或参数被忽略。
**根因**：verl 基于 Hydra——对**已存在的键**用 `+key=value` 会报错；对新键不加 `+` 会报错。
**修复**：
- 已存在键：直接 `key=value`；
- 新增键：`+key=value`（如 `+data.apply_chat_template_kwargs.enable_thinking=false`）。
**沉淀**：收到 Hydra override 报错先区分"键是否存在"；训练前用 `--cfg job` 类 dry-run 校验可省一轮启动（8 分钟模型加载）。

---

## 7. 镜像"抄作业"踩坑合集（启动前 30 分钟必查清单）

| 检查项 | 命令/方法 |
|---|---|
| 模型完整性 | 分片存在 + 非零 + `config.json` 架构断言 |
| 镜像 digest | 复制粘贴 + `docker manifest inspect` |
| 依赖清单 | 与接入方式匹配（见 §5） |
| kit 数据完整 | `sha256sum -c protocol.sha256` + 预检 |
| 字段完整 | `instances.jsonl` 含 `image_env`/`image_tcr`（见 05 §4） |
| 种子数据源 | parquet 与 instances 同源构建 |
