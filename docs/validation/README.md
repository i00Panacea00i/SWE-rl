# 最终验证阶段 · 计划总览（30B base vs base+LoRA pass@1 对比）

> **目标**：用**训练未见过的题**，对比 Qwen3-Coder-30B-A3B 基模与基模+LoRA（swegym-30b-tier0-r1, step-50）的 pass@1 差别——回答"这次 RL 训练到底有没有用"。
> **方法论**：grill-with-docs 访谈（2026-09-20）产出的 4 份 ADR + 术语表，一切在**开测前**锁定。

## 决策一览（全部已锁定）

| # | 决策 | 结论 | 记录 |
|---|---|---|---|
| 1 | 测试数据 | 86 题候选**全量双向验证**（预期 ~70 可用），tier0/tier1 分层报告；防泄漏双断言 | [ADR-001](ADR-001-heldout-dataset.md) |
| 2 | 对比协议 | **双协议**：temp0（主）+ temp0.7×n4（副）；8 项公平性锁定清单；两次独立运行 | [ADR-002](ADR-002-pass1-protocol.md) |
| 3 | 执行资源 | **重建 4×L20 节点**；verl val 路径（复用已验证链路）；base/LoRA 两组隔离 | [ADR-003](ADR-003-eval-infrastructure.md) |
| 4 | 判定与报告 | Δ>0 即认可（用户选定）+ **强制透明度条款**（Wilson CI + McNemar + 分层）；负结果如实报告 | [ADR-004](ADR-004-verdict-reporting.md) |

## 结果与复盘（2026-09-21）

**执行摘要**：主协议（temp0, n=1）与副协议（temp0.7, n=4）均已完成 40 题对照；
评估架构因 verl val 路径的共卡 OOM 改为**独立 vLLM driver**（判分栈与训练同源，
公平性保持；偏离记录见复盘文档 §3）。

| 指标 | base | lora (step-50) | 判定（ADR-004） |
|---|---|---|---|
| pass@1（temp0） | 5.0% (2/40) | 2.5% (1/40) | Δ 不显著 |
| pass@4（temp0.7） | 15.0% (6/40) | 10.0% (4/40) | Δ 不显著 |
| **轨迹级通过率** | **5.0% (8/160)** | **5.0% (8/160)** | **无提升（最有力）** |

**结论**：50 步 LoRA 训练未带来可测提升（**负结果，按 ADR-004 如实报告**）；
pass@4(15%) ≈ pass@1(5%) × 3 揭示"会做但不稳"；每题成功分布显示 85% 的题
4 次全败（零训练信号）——重训方向修正为**可学习区间数据 + n=8 采样**。

**完整复盘**：[pass4-test-design-postmortem.md](pass4-test-design-postmortem.md)
（协议设计 / 四轮缺陷链 / 结果有效性 / 下轮改进 checklist）

---

## 执行阶段

### P0 · 无 GPU 准备（可立即开始）
1. **86 题镜像预热**（`CreatePreCacheImageTask`，<5 分钟）
2. **双向验证**（baseline×1 + golden×2，并发 10，自动重试）→ 剔除假阳性/flaky/坏题（1~2 小时）
3. **测试集冻结**：held-out manifest（题单 + 剔除记录 + 校验和）+ 防泄漏双断言
4. **评估资产预写**：`configs/eval_base.sh` / `eval_lora.sh`、评估 Pod 清单、预检脚本

### P1 · 资源（并行/按需）
5. 重建 4×L20 节点：NAT 路由核查 → CFS PVC → secrets → 评估准备
6. **冒烟项**：val-only 模式 2 题验证（确认不触发训练更新）

### P2 · 执行（约 2-3 天）
7. `eval-base-t0`（主协议 base，~2-4h）
8. `eval-lora-t0`（主协议 LoRA，~2-4h）
   → **主结论在此产生**
9. `eval-base-t07` + `eval-lora-t07`（副协议 ×4，~8-16h each，可顺延）

### P3 · 分析交付
10. 统计：Δresolved / Wilson CI / McNemar / 分层 / 协议质量
11. 报告：`reports/eval-30b-base-vs-lora/`（固定模板，[ADR-004 §3](ADR-004-verdict-reporting.md)）
12. 归档三副本（本地+CFS+COS）+ GitHub 发布

## 红线（开测后不可违反）

- 公平性锁定清单（[ADR-002 §2](ADR-002-pass1-protocol.md)）任何一项不得漂移；
- 判定口径不得事后修改（[ADR-004 §1](ADR-004-verdict-reporting.md)）；
- 负结果必须如实报告（[ADR-004 §2](ADR-004-verdict-reporting.md)）。

## 风险与对策

| 风险 | 概率 | 对策 |
|---|---|---|
| 候选剔除率超预期（>30%） | 低 | 暂停复盘（区分"质量问题"与"平台暂时性"，见 troubleshooting 05 §3.3） |
| val-only 模式不可触发 | 中 | ADR-003 备选方案；首项冒烟先验 |
| 资源窗口不足 | 中 | 主协议优先；副协议顺延并标注 |
| 结果不显著/为负 | 存在可能 | 预注册失败预案：如实报告 + 根因分析（这本身是有效产出） |

## 关联文档

- 术语：[glossary.md](glossary.md)
- 数据验证工具：`sandbox/validate_swe_ags.py`（镜像覆盖+重试版）
- 训练完整报告：[reports/swegym-30b-tier0-r1](../../reports/swegym-30b-tier0-r1/README.md)
- 问题复盘：[docs/troubleshooting](../troubleshooting/README.md)（评估遇坑先查症状速查表）
