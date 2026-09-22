# 09 · 案例解剖：conan-14362 的一条 0 分轨迹（step-19）

> **一句话结论**：模型**"诊断正确、从不动手、格式致命"**——12 轮里 9 轮在读代码
> （`edit` 操作 **0 次**），第 12 轮唯一一次修复尝试被自身格式习惯（Python 围栏 + 注释）
> 杀死，最终提交 **0 字节补丁**，`reward=0`（f2p 0/2，p2p 32/32）。
>
> 证据：`artifacts/archive/cfs-traces-30b/traces/swegym-30b-tier0-r1/train/step-19/
> conan-io__conan-14362/6d120d88a30642dc9fa1014c2e774620/`

---

## 1. 轨迹速览

| 项 | 值 |
|---|---|
| 题目 | `conan-io__conan-14362`（CMAKE_SYSTEM_PROCESSOR 对 ARM64 设为 "armv8"，应为 "aarch64"） |
| 步/组 | step-19 首条采样（组内 4 条全部 0 分） |
| 终止 | `stop_reason: step_budget`（12 轮用满，**非 token 截断**） |
| 操作分布 | `inspect×6 + test×3 + execute×2 + format_error×1`——**edit = 0** |
| 判分 | f2p 0/2（2 个目标测试全挂）、p2p 32/32（回归全过） |
| 产出 | **candidate.patch = 0 字节** |
| 用时 | 12 轮 / 11 次 shell 操作 |

## 2. 十二轮完整还原（格式问题贯穿始终）

| 轮 | kind | exit | 模型输出的结构 | 实际发生 |
|---|---|---|---|---|
| 1 | execute | **127** | 纯散文（"Looking at the issue, I need to understand..."） | `Looking: command not found`——**空转** |
| 2 | inspect | 0 | "let me examine...\n`grep -n ...`" | `let` 报语法错 + **grep 碰巧执行成功** ✓ |
| 3-7 | inspect | 0 | 均为"散文句 + 真命令" | 同上：散文行报错、命令行**歪打正着**执行 ✓ |
| **8** | execute | **127** | **完整正确诊断**（见 §3.1），但**结尾无命令** | 整段被执行 → `_get_cross_build: command not found`——**说了但没做** |
| 9 | test | 1 | "Let me run the specific failing tests...\n`pytest ...::test_cross_arch`" | 测试执行（失败——确认现状） |
| 10 | test | **2** | 同型输出但**未闭合引号** | **语法预检拦截**："Incomplete/invalid shell action; not executed" |
| 11 | test | 1 | "Let me run the test differently...\n`pytest ...::test_cross_build`" | 测试执行（失败） |
| **12** | **format_error** | **2** | "Perfect! ... Let me fix this by modifying the blocks.py file..." + **\`\`\`python 围栏（内容为注释）** | **"Incomplete code fence; return a complete bash block without commentary"——修复意图被格式杀死** |

### 2.1 核心机制：解析器与执行的错位

`executed_command` 与 `action` **逐字相同**（第 2 轮实证）：

```
action:            "let me examine the file mentioned in the issue:\ngrep -n "CMAKE_SYSTEM_PROCESSOR" ..."
executed_command:  "let me examine the file mentioned in the issue:\ngrep -n "CMAKE_SYSTEM_PROCESSOR" ..."
```

→ 解析器**没有提取代码块**（模型本就没输出围栏），**整段当一条 shell 命令**推送沙箱；
→ bash 按换行分句：散文句报错（`let`/`Looking`/`Let` 均非常规命令），**命令句继续执行**——
这就是"9 轮读代码碰巧有效"的原因（**依赖 shell 容错，而非协议正确**）。

### 2.2 行为层：诊断正确，却从不行动（第 8 轮原文）

```
"Now I can see the issue. The problem is in the `_get_cross_build` method where
`system_processor` is set directly to `arch_host`, which for ARM64 is "armv8",
but CMake expects "aarch64" for ARM64 architecture.

Looking at the code, I need to fix the logic to map "armv8" to "aarch64" ...
Let me run the failing tests first to see the exact failure:"
```

——**根因与修复方案已 100% 正确**，但结尾只有"Let me..."，**没有任何命令** →
整段被执行 → 127 空转。**模型把"描述行动"当成了"执行行动"。**

### 2.3 收尾层：唯一修复尝试死于自身格式（第 12 轮原文）

```
"Perfect! Both tests are failing because ... Let me examine the exact function ...

```python
# I need to check the exact function that sets system_processor
# Let me find the exact function where arch_host is mapped to system_processor
```

Looking at the error ... Let me fix this by modifying the blocks.py file to properly ma"

判分观察：Action format error; no command executed:
        Incomplete code fence; return a complete bash block without commentary
```

——**用 ```python 围栏写注释**（不是 bash 命令）→ 解析器拒绝 → `format_error`；
且文本在 "to properly ma" 处中断（输出不完整）。**12 轮的终点：修复动作 0 字节。**

## 3. 跨 step 行为指纹（该题全程 75 次采样）

```
0B 空补丁     ≈ 50 次   ← 主模式（与全局 70.7% 空补丁率一致）
534B 补丁     6 次      ← 同一"半成品 A"反复出现
733B 补丁     8 次      ← 同一"半成品 B"，且 8 次中有 8 次 reward=0.5（f2p 1/2）
1424B 补丁    1 次      ← step-31 最大尝试（仍 0 分）
全过（1.0）   0 次      ← 75 次采样，该题从未被完全解决
```

**两个关键判读**：
1. **行为固化**：同一题在不同 step（不同模型版本、温度 0.7）下反复产出**完全相同大小的补丁**
   （733B ×8、534B ×6）——**输出多样性坍缩的直接证据**（呼应 `actor/entropy=0.385`）；
2. **不可学性**：75 次 0 全过，但 **8 次达到 1/2**（部分成功稳定存在）——
   该题对模型属"半可解"，**按难度筛选标准（1/4~3/4 成功率）处于边缘**，
   而它在训练池中被反复采样（20 题池 × 50 步），**低效消耗算力**。

## 4. 根因链（一张图）

```
┌ 格式习惯（输入侧）
│  模型从不输出"纯命令块"；固定"散文 + 可选命令"
│    ├─ 无命令 → exit 127 空转（[1][8]）
│    ├─ 有命令 → 靠 bash 换行容错碰巧执行（[2]-[7][9][11]）
│    └─ 围栏错用（```python 写注释）→ format_error（[12]）
├ 行为模式（决策侧）
│  9/12 轮只读不写；把"描述意图"当"执行"；edit=0
├ 预算结局（收尾侧）
│  step_budget 用满（12 轮）；修复尝试恰在第 12 轮且被格式杀死
└ 训练信号（反哺侧）
   本次 reward=0 → 该组 4 条全 0 → 零优势 → 无梯度（74.6% 零优势组的缩影）
```

## 5. 对训练的六条启示（可直接落地）

| # | 启示 | 动作 |
|---|---|---|
| 1 | **协议必须先于能力**："散文+命令"应被解析器**显式拒绝并回送纠错提示**（而非依赖 bash 容错） | 收紧 `parse_action`：无代码块 → 直接返回格式提示（当前宽容策略产生了 10.4% 的 127 轮次） |
| 2 | **"说而不做"需要行为塑造**：诊断正确却无动作的轮次应给负向信号或提示 | 在 observation 中附加"你上轮只描述了计划但未给出命令"的模板反馈 |
| 3 | **format_error 发生在最关键时刻**（修复前一步）→ 代价最大 | prompt 中强化"每个回复必须且只能包含一个完整 bash 块"；对围栏类型做白名单（仅 bash） |
| 4 | **该题不可学（75 次 0 全过）**——继续采样是纯浪费 | **难度筛选**（pass@4 画像）：把该题从训练池剔除（详见 `training-config-audit.md` §6） |
| 5 | **多样性坍缩**（同补丁尺寸反复出现）需要熵干预 | `entropy_coeff > 0` 或提高采样温度（当前 entropy=0.385 极低） |
| 6 | 本案例的完整数据（75 次采样 × 判分）应作为**回归基准** | 重训后用相同统计检验行为是否改善（空补丁率/只读率/格式错误率） |

## 6. 附录 · 证据文件索引

| 文件 | 内容 |
|---|---|
| `.../6d120d88.../episode.json` | 12 轮完整记录（action/executed_command/observation/exit_code/token） |
| `.../6d120d88.../candidate.patch` | 0 字节（空补丁） |
| `.../6d120d88.../judge/result.json` | reward=0 / f2p 0/2 / p2p 32/32 |
| `.../6d120d88.../judge/test.log` | "2 failed, 32 passed in 7.62s" 完整输出 |
| 跨 step 统计 | 75 次采样（本文 §3，可用 `judge/result.json` 重算） |
