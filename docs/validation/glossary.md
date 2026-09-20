# 术语表（Validation Glossary）

> 最后测试验证阶段全部术语的权威定义。所有文档/报告必须使用本表的措辞。

## 实验设计

| 术语 | 定义 |
|---|---|
| **held-out（留出集）** | 训练与训练期评估**从未使用**的题目；模型在训练中没见过这些题的题面/补丁/测试 |
| **双向验证（dual verification）** | 一道题进入任何集合前必过：baseline×1（期望全失败，测假阳性）+ golden×2（期望全通过，测可用性/一致性） |
| **假阳性题（baseline pass）** | baseline 无补丁却 F2P 通过 → 题目"生来就对"，剔除（指标稀释源） |
| **flaky 题** | golden 两次运行结果不一致 → 结果随机，剔除 |
| **坏题（f2p_fail）** | golden 补丁也无法全过 F2P → 题面/镜像有问题，剔除 |
| **分层报告（stratified）** | 按难度层（tier0 同分布 / tier1 泛化）分别统计与展示 |
| **预注册（pre-registration）** | 在开测**之前**书面锁定判定标准与报告口径，防止事后挑数据 |

## 指标

| 术语 | 定义 |
|---|---|
| **pass@1** | 每题采样 1 条轨迹，`resolved=True` 记为通过；通过题数 / 总题数 |
| **pass@n（best-of-n）** | 每题采样 n 条，任一条 resolved 即算通过（本项目副指标为 temp0.7 × n=4） |
| **resolved** | F2P 全部通过 **且** P2P 无回归（与 SWE-bench 官方口径一致） |
| **F2P / P2P** | fail-to-pass（应从失败变通过的测试）/ pass-to-pass（必须保持通过的回归测试） |
| **f2p_rate** | F2P 通过数 / F2P 总数（0~1 连续值）——比 0/1 的 resolved 更细粒度 |
| **Δresolved** | pass@1(LoRA) − pass@1(base)，单位百分点（pp） |
| **Wilson 95% CI** | 二值比例的置信区间（小样本比正态近似更可靠） |
| **McNemar 检验** | 配对二值对比的显著性检验（同一题两模型结果构成的 2×2 表：only-base / only-loRA / both / neither） |

## 采样与执行

| 术语 | 定义 |
|---|---|
| **greedy / temp 0** | 确定性解码（每步取最高概率 token）——pass@1 的标准协议 |
| **temperate 采样（temp 0.7）** | 与训练 rollout 同分布的解码（随机性保留） |
| **双协议（dual protocol）** | 主指标 temp0（标准）+ 副指标 temp0.7×4（训练分布视角） |
| **base 组** | Qwen3-Coder-30B-A3B 原始权重（无适配器） |
| **LoRA 组** | base + `swegym-30b-tier0-r1` 训练产出的 LoRA 适配器（step-50） |
| **公平性锁定清单** | 两组的 8 项完全一致配置（prompt / template / 上下文 / 步数 / 判分 / 沙箱 / 工具链 / 采样环境），唯一变量 = 模型 |
| **run_id** | 一次评估运行的唯一标识（base 与 LoRA 为两次独立运行） |
