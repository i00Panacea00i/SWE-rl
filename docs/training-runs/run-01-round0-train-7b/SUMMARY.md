# Run 01 · round0-train（7B 基线首跑）

| 项 | 内容 |
|---|---|
| 日期 | 2026-09-11 |
| 模型 | Qwen2.5-Coder-7B（单卡 L20 44GB） |
| 数据 | 12 题（SWE-bench 早期手工题池） |
| 步数 | 8 步 |
| 结果 | 指标全零：`critic/score/max=0`、`advantages/max=0`、`grad_norm=0` |
| 状态 | ❌ 终止——诊断后确认为**"算法正确行为"而非缺陷** |

## 目标
打通 RL 训练全链路（项目首个端到端运行）。

## 遇到的问题与解决方案

### 问题 1：全零奖励（看起来像框架 bug）
**现象**：8 步训练全部指标恒 0，无法区分"链路故障"与"模型不会"。

**诊断**（六步取证 + CPU 隔离回放）：奖励链路（judge → rm_scores → GRPO scores）
逐段验证正确；评分器区分度测试 9/9 通过（baseline 全 0、golden 全 1）。

**根因**：**算法正确行为**——7B 模型 0/12 题能解出，GRPO 组内奖励全相同 →
优势恒 0 → 无梯度。这是数学必然，不是代码错误。

**解决方案**：
1. 训练批次设为全题数（确保每组覆盖不同题目）+ `rollout.n ≥ 4`（组内多样性）；
2. 接受"模型太弱 → 无信号"的物理事实，启动模型升级路线（7B → 14B → 30B）。

## 沉淀
- **零奖励分水岭**：`score/max` 是否为 0——是则"模型没解出任何题"（非框架 bug）；
  `score>0 但 adv=0` 才是链路问题。
- 详解：`docs/troubleshooting/05-data-judging.md §1`

## 产物
- 诊断证据与隔离回放：`artifacts/grpo-diagnosis-20260911/`
  （`isolated_test.py`、`replay_fixed_judge.py`、`evidence/`、`REPORT.md`）
