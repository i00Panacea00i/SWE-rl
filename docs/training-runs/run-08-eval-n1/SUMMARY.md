# Run 08 · eval-base vs eval-lora（主协议评估，n=1）

| 项 | 内容 |
|---|---|
| 日期 | 2026-09-20 |
| 对象 | base（Qwen3-Coder-30B-A3B）vs lora（Run 07 step-50 合并模型） |
| 协议 | 40 题 heldout（与训练 0 重叠）、n=1、temp=0（greedy） |
| 结果 | **base 5.0%（2/40）vs lora 2.5%（1/40）**——差异不显著 |
| 状态 | ✅ 完成（含架构级修复） |

## 目标
回答"这次 RL 训练到底有没有用"——训练未见过的题上的 A/B 对照。

## 遇到的问题与解决方案（本 run 的最大工程事件）

### 问题 1：verl val 路径连续 5 次 OOM（差 192MB）
**现象**：评估路径的 `update_weights`（初始权重同步）稳定 OOM——
actor 28.59GB + vLLM 权重唤醒 15.61GB = 44.2/44.39GB，差 192MB。
5 次配置尝试（关 KL/降 util/缩 response/降 batch）全部无效 → **结构性上限**。

**根因**：verl 共卡架构（FSDP actor + ref + vLLM colocate）在 44GB 单卡上的
结构性显存上限；训练路径能过纯属分配模式差异。

**解决方案（架构级）**：**独立 vLLM 评估 driver**（`controller/eval_driver.py`）——
vLLM 独占显存纯推理（15.3GB 权重 + KV），复用训练同源的判分组件
（`EpisodeSession`/`evaluate_patch`）→ **零 OOM，40 题 16 分钟**。

### 问题 2：vLLM 不支持 Qwen3-MoE 的 k_proj/o_proj LoRA
**现象**：`ValueError: ...k_proj.lora_A... is unsupported LoRA weight`。
**解决方案**：**离线合并 LoRA**（`W + α/r·B@A`，192/18867 张量）→ 得到普通完整
模型（56.9GB），vLLM 常规加载。

### 问题 3：镜像 transformers 5.5.3 缺 HybridCache（peft 路径不可靠）
**解决方案**：改**纯 safetensors 权重级合并**（`controller/merge_lora_native.py`），
不导入 transformers，纯 CPU，零 GPU 计费。

## 沉淀
完整复盘：`docs/troubleshooting/08-eval-standalone-vllm.md`（四段式）

## 产物
- 评估清单：`eval-base.yaml` / `eval-lora.yaml`（及 t07 变体）
- 轨迹：CFS `traces/eval-{base,lora}-t0/vllm/`（各 41 条目 + summary.json）
