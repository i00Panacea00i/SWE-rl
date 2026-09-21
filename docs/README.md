# 文档中心 · 审查导航（docs/）

> 按**阅读顺序**组织的文档地图。全部文档基于**真实运行数据**（含负结果），
> 每条关键结论均附证据位置。最近更新：2026-09-21。

---

## 🧭 领导审查路线（约 45 分钟看完全貌）

| 顺序 | 文档 | 内容 | 时长 |
|---|---|---|---|
| **1** | [`overview/training-architecture-overview.md`](overview/training-architecture-overview.md) | **系统全景**：四层架构 / verl / AGS 沙箱 / 数据流 / 实测结果（含扩卡申请论证） | 15 min |
| **2** | [`overview/tke-gpu-cluster-usage.md`](overview/tke-gpu-cluster-usage.md) | **TKE GPU 集群使用报告**：节点规格 / 资源账（显存·内存·存储）/ 性能实测 / 扩容论证 | 10 min |
| **3** | [`overview/training-loop-flow.md`](overview/training-loop-flow.md) | **训练闭环流程全解**：SandBox 采集 tracing → TKE 训练 → 新模型回 SandBox 验证 | 10 min |
| **4** | [`training-runs/README.md`](training-runs/README.md) | **9 次训练/评估的时间线** + Top 问题与解决方案 + 关键数字 | 10 min |
| **5** | [`validation/pass4-test-design-postmortem.md`](validation/pass4-test-design-postmortem.md) | **效果验证结论**：训练到底有没有用（负结果如实报告）+ 测试设计复盘 | 10 min |
| **6** | [`overview/training-config-audit.md`](overview/training-config-audit.md) | **问题根因审计**（16 项分级）+ 改进方案（10 项 P0） | 10 min |

---

## 📚 按主题浏览

### `overview/` · 总览与核心报告

| 文档 | 内容 | 更新 |
|---|---|---|
| [training-architecture-overview.md](overview/training-architecture-overview.md) | 系统全景架构与训练实录（四层架构 / 数据流 / 术语表） | 09-20 |
| [tke-gpu-cluster-usage.md](overview/tke-gpu-cluster-usage.md) | **TKE GPU 集群使用报告**（资源账 / 性能 / 运维六条 / H20 扩容论证） | 09-21 |
| [training-loop-flow.md](overview/training-loop-flow.md) | **训练闭环流程**（SandBox tracing → TKE 训练 → 新模型回 SandBox + 数字账） | 09-21 |
| [pod-ags-communication.md](overview/pod-ags-communication.md) | Pod ↔ AGS 通信全链路手册（三层架构 / 7 步生命周期 / 4 组真实数据案例） | 09-21 |
| [training-config-audit.md](overview/training-config-audit.md) | 训练配置全面审计（16 项问题 / 实测 × 基准三角验证 / P0-P2 方案） | 09-21 |

### `training-runs/` · 训练与评估全记录（9 次运行）

| 入口 | 内容 |
|---|---|
| [training-runs/README.md](training-runs/README.md) | **总索引**：时间线总表 + 阶段叙事 + Top 问题 + 关键数字 |
| `run-01 ~ run-09/` | 每次运行一个独立文件夹（`SUMMARY.md` = 目标/问题/方案/产物 + 实物清单） |

### `validation/` · 评估协议与复盘

| 文档 | 内容 |
|---|---|
| [validation/README.md](validation/README.md) | 验证阶段计划（4 份 ADR：测试集 / 协议 / 架构 / 判定）+ 结果摘要 |
| [validation/pass4-test-design-postmortem.md](validation/pass4-test-design-postmortem.md) | pass@4 测试设计复盘（协议 / 四轮缺陷链 / 有效性 / 改进 checklist） |
| `ADR-001 ~ 004` + 术语表 | 开测前锁定的协议资产 |

### `troubleshooting/` · 排障档案（8 篇 + 速查表）

| 入口 | 内容 |
|---|---|
| [troubleshooting/README.md](troubleshooting/README.md) | 症状速查表（按报错关键词定位）+ 运行年表 |
| `01 ~ 08` | 运行复盘 / 基础设施 / 沙箱 / 训练引擎 / 数据判分 / Agent 协议 / 工程工具箱 / 评估架构 |

### `infrastructure/` · 平台与基础设施

| 文档 | 内容 | 状态 |
|---|---|---|
| [ags_image_override.md](infrastructure/ags_image_override.md) | AGS 镜像覆盖方案（1 个通用工具服务 N 道题，含实测证据） | ✅ 现行 |
| [ags_tool_setup.md](infrastructure/ags_tool_setup.md) | 旧"逐题建工具"方案 | 🕐 已被取代 |
| [tokyo_gpu_plan.md](infrastructure/tokyo_gpu_plan.md) | 跨区链路规划（§0 时延评估仍有参考价值） | 🕐 部分参考 |

### `archive/` · 历史文档（已过时，留档追溯）

| 文档 | 说明 |
|---|---|
| [PROJECT_REPORT.md](archive/PROJECT_REPORT.md) | 2026-09-11 阶段汇报（当时指标未达标；后续问题均已解决） |
| [rl-pipeline-report.md](archive/rl-pipeline-report.md) | 2026-09-11 RL 流水线报告（基于 14B 运行） |
| [PHASE_A_STATUS.md](archive/PHASE_A_STATUS.md) | 2026-09-10 Phase A 冒烟状态 |

---

## 相关目录（仓库内其他位置）

| 位置 | 内容 |
|---|---|
| [`../reports/swegym-30b-tier0-r1/`](../reports/swegym-30b-tier0-r1/) | 训练完整报告（README / REFERENCE / 指标 CSV / 图表 / 配置） |
| `../artifacts/archive/pass4-eval-20260921/` | pass@4 全量数据归档（320 轨迹 + 判分证据，本机） |
| `../artifacts/archive/training-runs/` | 训练归档本机副本（与 `training-runs/` 同源） |
| `../briefing/` | 内部汇报材料（不随仓库发布） |
