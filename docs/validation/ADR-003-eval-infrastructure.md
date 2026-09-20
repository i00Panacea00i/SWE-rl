# ADR-003：评估执行架构与资源

- **状态**：已决定（2026-09-20）
- **前置**：[ADR-002](ADR-002-pass1-protocol.md)（协议）

## 背景

评估是**纯推理**负载（无训练/无梯度），但 30B 权重 61GB 决定单卡 48GB 装不下——最低 2×L20（TP=2），推荐 4×L20。TKE 节点已退还，需重建。

评估载体有三个候选：

| 候选 | 可行性 | 风险 |
|---|---|---|
| A. **verl val 路径**（`val_before_train` + val-only） | ✅ 该链路在 30B 训练中已验证（输出 `val-aux/swe-bench-ags/reward/mean@1`） | val-only（`total_training_steps=0`）触发方式需冒烟确认 |
| B. 独立 driver（vLLM server + 复用 `episode.py`） | 需新写生成循环（与 AgentLoop 耦合需解耦） | 新代码 = 新变量（违背"复用已验证路径"原则） |
| C. vLLM + OpenAI 兼容 API + 手工脚本 | 简单 | 与训练 AgentLoop 行为差异大（token 对齐/tracing 全丢） |

## 决策

### 1. 资源：重建 4×L20 节点（用户选定）

- 规格复刻训练环境：`PNV5b.32XLARGE384`（4×L20 / 128C / 384GB）；
- 部署按 [reports/README §2](../../reports/swegym-30b-tier0-r1/README.md)：NAT 路由 → CFS PVC → secrets（ags-credentials / tccli-credential）→ 评估 Pod；
- 窗口：4 次 val 运行 ≈ 2-3 天（主协议单次 ~2-4h，副协议 ~8-16h）。

### 2. 执行载体：verl val 路径（候选 A）

- 评估集 = held-out manifest（parquet 形式，由 held-out 题构建）；
- 运行模式：`trainer.val_before_train=True` + val-only 触发（`total_training_steps=0`，**首个冒烟项**：2 题小验证确认此模式不触发训练更新）；
- 若 val-only 不可行 → 降级方案：`total_training_steps=1` 且第一步前终止（val 已完成后 kill）——一句话记录于运行手册；
- 备选（万一 A 有不可解阻塞）：实现候选 B，与 A 的结论须交叉核对（**同一模型、同一题** pass 结果一致）。

### 3. 两次独立运行（run_id 隔离）

| 运行 | 模型 | LoRA 字段 | resume |
|---|---|---|---|
| `eval-base-t0` / `eval-base-t07` | 基座（61GB safetensors） | ❌ 不配置（无 adapter） | disable |
| `eval-lora-t0` / `eval-lora-t07` | 基座 + step-50 LoRA | ✅ rank 32 / alpha 64 / attention-only | `auto`（从 `global_step_50` 加载） |

- LoRA 加载路径已由训练断点续训验证过（`Loaded LoRA-only checkpoint (384 keys)`）；
- 主/副协议差异**仅**在 `val_kwargs`（`n` 与 `temperature`）——列于公平性锁定清单之外的两个合法变量（协议维度，非模型维度）。

### 4. 产物与落盘（与训练同构）

```
/mnt/cfs/swe-rl/traces/eval-<run_id>/val/step-0/<instance>/<episode_id>/
├── episode.json       # 逐轮动作/观察/奖励（解析脚本复用）
├── candidate.patch    # 模型补丁
└── judge/result.json  # 判分明细（resolved / f2p / test_states）
```

- 评测 Pod 日志 + GPU 采样落 `logs/eval-<run_id>/`；
- 完成后立即拉回本地归档（1MB 分块协议，`07-eng-toolbox.md §1`）。

### 5. 平台侧准备（无 GPU 阶段完成）

1. 86 题双向验证（[ADR-001](ADR-001-heldout-dataset.md)）→ held-out manifest；
2. held-out 的 task_specs/instances 校验（`protocol.sha256` 扩展）；
3. 评估配置脚本（`configs/eval_base.sh` / `eval_lora.sh`）与 Pod 清单**预写**；
4. 评估前预检：`python -m sandbox.preflight`（路由一致性）+ 镜像预热核对。

## 后果

- 正面：载体是已验证路径（训练期 val 的工程风险已暴露过）；两次运行的隔离使"适配器残留"类污染不可能。
- 负面：4 卡 2-3 天的资源成本；val-only 触发方式存在冒烟不确定性（已列为第一执行项）。
- 风险与对策：平台波动（沙箱创建竞态/预热失效）→ 自动重试已内置；评估中断 → 每题单独落盘，支持断点续跑（幂等跳过已完成题）。
