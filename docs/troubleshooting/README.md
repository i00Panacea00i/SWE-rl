# 训练问题复盘与沉淀（Troubleshooting Archive）

> **范围**：本项目从零到 30B-MoE 训练完成（2026-09-09 ~ 09-20）期间**全部失败运行与 bug 报错**的归档沉淀。
> **用法**：先看下方"症状速查表"定位 → 跳转对应文档；每篇文档内每条问题均为「现象 → 根因 → 修复 → 沉淀」四段式。

## 文档地图

| # | 文档 | 覆盖范围 |
|---|---|---|
| 1 | [01-runs-postmortem.md](01-runs-postmortem.md) | **历次训练运行复盘**：7 次运行的时间线、终止原因、转折点 |
| 2 | [02-infrastructure.md](02-infrastructure.md) | 基础设施与集群：NAT 出口、集群迁移、公网 API、DNS 误判、镜像拉取 |
| 3 | [03-sandbox-ags.md](03-sandbox-ags.md) | 沙箱平台（AGS）：工具配额、镜像覆盖、预热、创建竞态、凭证限流、环境激活 |
| 4 | [04-training-engine.md](04-training-engine.md) | 训练引擎与资源：显存 OOM 链、CPU 内存 OOM、权重同步、断点续训、依赖缺失 |
| 5 | [05-data-judging.md](05-data-judging.md) | 数据与判分：GRPO 零奖励诊断、判分器鲁棒性、假阳性/flaky/坏题过滤 |
| 6 | [06-agent-protocol.md](06-agent-protocol.md) | Agent 协议与模型输出：format_error、action_tokens、thinking 模式、MoE-LoRA 策略 |
| 7 | [07-eng-toolbox.md](07-eng-toolbox.md) | 工程工具箱：大文件传输、跨区上传、YAML/heredoc、Pod 运维、验证技巧 |
| 8 | [08-eval-standalone-vllm.md](08-eval-standalone-vllm.md) | **评估阶段 OOM 与独立 vLLM 架构**：val 路径 5 次 OOM、共卡显存极限、独立 driver、LoRA 离线合并、上下文预算 |
| 9 | [09-case-study-conan-14362.md](09-case-study-conan-14362.md) | **案例解剖：一条 0 分轨迹的病理**（诊断正确却从不行动 / 格式致命 / 75 次采样行为指纹 / 根因链与 6 条启示） |

## 症状速查表（按报错关键词）

| 看到的报错/现象 | 去这里 |
|---|---|
| `loss` 全 0 / `advantages/max=0` / `grad_norm=0` | [05 §1 零奖励诊断](05-data-judging.md) |
| `critic/score/max=0` 且模型一个题都做不出来 | [05 §1](05-data-judging.md) + [06 §4 模型选型](06-agent-protocol.md) |
| `CUDA out of memory`（显存） | [04 §1 显存 OOM 链](04-training-engine.md) |
| `RayTaskError(OutOfMemoryError)` / Ray 杀 worker | [04 §2 CPU 内存 OOM](04-training-engine.md) |
| `KV cache` 不足 / `max_model_len` 相关 | [04 §1.2](04-training-engine.md) |
| `update_weights` 阶段 OOM | [04 §1.3](04-training-engine.md) |
| 评估路径 `update_weights` OOM（差 ~200MB，配置调不动） | [08 §1-2 独立 vLLM 方案](08-eval-standalone-vllm.md) |
| `... is unsupported LoRA weight`（vLLM 加载 LoRA） | [08 §4.1 离线合并](08-eval-standalone-vllm.md) |
| `cannot import name 'HybridCache' from 'transformers'` | [08 §4.2 权重级合并](08-eval-standalone-vllm.md) |
| `maximum context length is 16384 tokens`（评估 driver） | [08 §4.3 预算管理](08-eval-standalone-vllm.md) |
| 补丁恒为空 / 模型只读不写 / `exit_code=127` 空转 / `Incomplete code fence` | [09 案例解剖](09-case-study-conan-14362.md) |
| `KeyError: 'image_env'` / 预检失败 | [05 §5 字段缺失](05-data-judging.md) |
| `Mixed prose/code fences` / `format_error` | [06 §1 宽容解析](06-agent-protocol.md) |
| `ModuleNotFoundError: tencentcloud` | [04 §5 依赖缺失](04-training-engine.md) |
| `RequestLimitExceeded`（OAuth 刷新） | [03 §4 凭证限流](03-sandbox-ags.md) |
| `image is still preparing` | [03 §2 镜像预热](03-sandbox-ags.md) |
| `409 ... CREATING`（沙箱创建竞态） | [03 §3 创建竞态](03-sandbox-ags.md) |
| `ImagePullBackOff`（镜像拉不下来） | [02 §5 镜像拉取](02-infrastructure.md) |
| `ImagePullBackOff`（digest 抄错） | [02 §5.2](02-infrastructure.md) |
| `Unable to connect to the server`（kubectl） | [02 §3 集群访问](02-infrastructure.md) |
| `dial tcp ... i/o timeout`（API server） | [02 §4](02-infrastructure.md) |
| 域名解析到 `0.0.0.1`（疑似平台故障） | [02 §2 DNS 误判](02-infrastructure.md) |
| `No module named 'tencentcloud'` | [04 §5](04-training-engine.md) |
| kubectl cp 大文件截断 / `connection reset` | [07 §1 分块传输](07-eng-toolbox.md) |
| COS 上传 `upload_part fail after max_retry` | [07 §2 跨区上传](07-eng-toolbox.md) |
| 判分器异常（`SystemCheckError` / `judge_error`） | [05 §2 判分降级](05-data-judging.md) |
| baseline 出现测试通过（假阳性） | [05 §3 双向验证](05-data-judging.md) |
| golden 通过率不稳定（flaky） | [05 §3.2](05-data-judging.md) |
| 模型输出思考文本而非命令 | [06 §3 thinking 模式](06-agent-protocol.md) |
| 命令被截断（少半截） | [06 §2 action_tokens](06-agent-protocol.md) |

## 运行年表（一图流）

```
09-09 基础设施搭建（VPC/集群/CFS）
09-10 Phase A 冒烟（沙箱拉通）
09-11 round0-train (7B)          → 全零奖励（正确算法结果；模型太弱）
09-11 recovery-14b-adapter-v2    → 零奖励 + 判分器 RuntimeError 终止
09-12 recovery-14b-fullbatch-v2  → 有正奖励！但判分器崩溃（fatal-log 终止）
09-13 recovery-14b-fullbatch-v3  → 同上
09-14 fullbatch-v4 深度诊断       → 判分器降级修复（SystemCheckError→0 分）
09-17 平台大变更（旧工具消失/裸域黑洞误判 → 化解）
09-17 swegym-7b-tier0-r1         → 跑通 23 步；0.7% 成功率（能力瓶颈确认）
09-18 swegym-9b-tier0-r1         → 多模态/单卡极限，十余项启动障碍（未完成）
09-18 swegym-30b-tier0-r1 (4×L20) → ✅ 50/50 步完成（本仓库主成果）
09-19~20 归档 / COS / GitHub 发布
09-20 eval-base vs eval-lora (4×L20) → ✅ 独立 vLLM 架构跑通双组对照（base 5% / lora 2.5%）
```

> 每次运行的详细终止原因与根因见 [01-runs-postmortem.md](01-runs-postmortem.md)。
