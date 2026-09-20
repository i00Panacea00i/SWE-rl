# ADR-002：pass@1 对比协议与公平性锁定

- **状态**：已决定（2026-09-20）
- **前置**：[ADR-001](ADR-001-heldout-dataset.md)（测试集）

## 背景

对比实验的唯一合法形态：**除模型外一切相同**。任一配置漂移都会把"协议差异"伪装成"模型差异"。
温度选择存在两难：pass@1 标准定义为 greedy（temp 0），而 LoRA 的训练分布是 temp 0.7——单协议都无法完整回答"训练是否有效"。

## 决策

### 1. 双协议（用户选定）

| 协议 | 配置 | 每组轨迹数 | 回答的问题 |
|---|---|---|---|
| **主指标** | temp 0（greedy），n=1 | N 题 × 1 | 标准 pass@1 对比（确定性） |
| **副指标** | temp 0.7，n=4 | N 题 × 4 | 训练分布下的改善（可算 pass@1 与 best-of-4） |

执行顺序：主协议先跑（成本低、结论核心）；副协议随后（或按资源窗口顺延）。

### 2. 公平性锁定清单（8 项，两组的配置必须逐字节一致）

| # | 项目 | 锁定值 |
|---|---|---|
| 1 | SYSTEM_PROMPT | `data/prepare_data.py` 中的版本（生成 parquet 时固化） |
| 2 | Chat template 参数 | `enable_thinking=false` |
| 3 | 上下文上限 | `max_model_len=16384`（prompt 4096 / response 8192） |
| 4 | Agent 步数上限 | `max_steps=12`（配置值；实际轮数逐轨迹记录并对比） |
| 5 | 动作预算 | `action_tokens=2048` / `observation_tokens=512` |
| 6 | 判分 | 官方 eval.sh + F2P 口径 + 三级降级（`harness.py` 同一版本） |
| 7 | 沙箱 | 同镜像（held-out 题各自 TCR 镜像）+ 同资源规格 + 同超时 |
| 8 | 工具链 | 冻结 kit（`protocol.sha256` 校验）+ 同一 vLLM 版本 |

**唯一变量：模型** = `base`（无适配器） vs `base + LoRA`（`hf-adapter` step-50）。

### 3. 执行隔离

- base 与 LoRA 为**两次独立运行**（各自 run_id：`eval-base-*` / `eval-lora-*`），不共享 vLLM 实例——避免 KV 缓存/适配器残留污染。
- 两次运行使用**同一份冻结 kit** 与**同一份 held-out manifest**（校验和比对）。

### 4. pass@1 / pass@4 计算口径

```
pass@1 = resolved 题数 / 总题数            （主协议：单条轨迹）
best-of-4 = 任一条 resolved 的题数 / 总题数（副协议）
f2p_rate = F2P 通过数均值（连续辅助指标）
```

### 5. 防"隐性不公平"的检查项

- **提示泄漏检查**：SYSTEM_PROMPT/USER_TEMPLATE 中不得出现测试题的 gold patch 信息（与训练同源，天然一致——构建时断言）；
- **题面一致性**：两组的 parquet/instances **同一文件**（哈希比对）；
- **时间漂移**：两次运行在**同一节点、相邻时间窗**执行（平台状态、网络环境尽量同构）。

## 后果

- 正面：双视角证据（标准 + 训练分布）；配置冻结使任何结论都不可被"配置漂移"反驳。
- 负面：副协议成本 ×4（可延后执行）；总轨迹数 = N×2×5（主 2N + 副 8N）；按 N≈70 计：主 140 条、副 560 条。
- 风险：N 不足时统计力受限——以 [ADR-004](ADR-004-verdict-reporting.md) 的报告纪律兜底。
