# 06 · Agent 协议与模型输出问题（Protocol & Model Output）

> 动作解析、token 预算、thinking 模式、MoE-LoRA 策略——"模型 vs 协议"接口层的全部坑位。

---

## 1. 动作解析失败率 45%——`Mixed prose/code fences` ⭐

**现象**：30B 训练 step-1 起，轨迹中 `kind=format_error` 占比 **45%**（106/238 步）；reward 大量为 0；模型原始输出形如：

```
Looking at the issue, it seems like there's a problem with patches not being found…
Let me first examine the failing tests to understand the issue better.

```bash
python -m pytest -rA --no-header -p no:cacheprovider … conans/test/…
```
```

**根因**：旧解析器要求"纯代码块开头的输出"——看到文本前缀 + 代码块混排即报 `Mixed prose/code fences`，**命令一字不差地被丢弃**。这是"模型行为（先思考再行动）"与"解析器假设（只输出命令）"的错位。

**修复（宽容解析，`sandbox/action_protocol.py`）**：
```python
if "```" in raw:
    # 提取第一个 fenced block（容忍前后说明性文字）
    m = re.search(r"```(?:bash|sh)?[ \t]*\n(.*?)\n[ \t]*```", raw, re.S)
    text = m.group(1)
    if raw[m.end():].strip() == "SUBMIT":
        outer_submit = True
```
- 无代码块 → 整段视为命令（裸命令路径不变）；
- 块后独立 `SUBMIT` → 提交信号保留。

**效果（同题同模型对比）**：format_error **45% → ~0%**；有效操作 132 → 558 步（step-1 内）；之后出现满分轨迹（2 条，reward=1.0）。

**沉淀**：
- **解析器与服务对象要对齐设计**：「严格解析 + 弱模型」= 全部信号丢失；「宽容提取 + 严格判分」= 信号通畅；
- 宽容 ≠ 放松判分：奖励仍只由官方测试决定，宽容只影响"命令能否被执行"。

---

## 2. 动作 token 预算不足——命令被截断

**现象**：轨迹中的命令在仓库路径中途被截断：`… -p no:snail con`（应为 `conans/…`）；命令执行必然失败。

**根因**：`action_tokens`（每轮动作生成上限）不足——模型先输出思考文本（占预算）再给命令，1280 token 内命令尾部被切。

**修复**（`configs/swe_agent.yaml`）：
```yaml
# 1280 → 2048：为"思考 + 完整命令"留足预算
action_tokens: 2048
```

**沉淀**：
- 动作预算要按"最长的模型行为"配置，不是"最长命令"；
- 诊断信号：命令尾部的截断特征 + `response_length/clip_ratio` 偏高；
- 与宽容解析协同：宽容解析消化 prose，token 预算保证命令完整。

---

## 3. thinking 模式破坏动作协议

**现象**：训练（及 base 模型）输出大段"内心独白"，未见可执行动作。

**根因**：Qwen3.5 系列 chat template 有 `enable_thinking` 开关（默认开）——思考块会掺进动作（解析器只能拿到思考文本或思考+动作混排）。Qwen3-Coder 模板无此变量（本身非 thinking 模型）。

**修复**（verl 原生支持透传）：
```
+data.apply_chat_template_kwargs.enable_thinking=false
```

**沉淀**：**换模型先读 chat_template**——是否存在 thinking/reasoning 开关、默认值是什么；RL 动作协议需要"确定性输出格式"。

---

## 4. MoE 模型的 LoRA 挂载策略

**现象（设计决策）**：`target_modules=[q,k,v,o,gate,up,down]` 在 MoE 上会把 LoRA 挂到**全部 128 个专家**的 `gate/up/down_proj`（同名匹配）——估算 ~2.2B LoRA 参数、Adam 状态 17.6GB、且每步只有 8/128 专家被激活，更新极稀疏。

**决策**：**attention-only**——`target_modules=[q_proj,k_proj,v_proj,o_proj]`：
- 参数量 ~58M（checkpoint 166MB）而非 2.2B；
- RL 微调的行为调整主要由 attention 承载；专家更新稀疏性不值得其成本；
- vLLM/peft 对 attention-LoRA 的加载路径最成熟。

**沉淀**：MoE + LoRA 的默认诱惑（"全部线性层"）是陷阱——**按"激活频率 × 参数量"选挂载点**。

---

## 5. 协议质量的可观测性（诊断工具）

从轨迹统计每步协议质量（`controller/parse_traces.py`）：

| 指标 | 含义 | 健康值 |
|---|---|---|
| `format_errors / rollout` | 解析失败率 | < 1（修复后≈0）|
| `valid_actions / rollout` | 有效操作数 | ~10-11 |
| `edits / rollout` | 实际改代码的操作 | > 0（有编辑行为）|
| `tests_run / rollout` | 主动跑测试 | > 0 |

**用途**：把"模型输出是否可用"变成可绘制的曲线——**协议问题在 reward 曲线上看不见，但在这些图上无所遁形**（仪表盘图见 `reports/swegym-30b-tier0-r1/figs/training_dashboard.png` 左下）。

**沉淀**：RL 训练的观测体系要覆盖三层：**奖励（效果）→ 协议质量（接口）→ 操作分布（行为）**——只盯 reward 会漏掉 45% 的浪费。
