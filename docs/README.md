# 文档索引（docs/）

> 本页是项目文档地图。**现行文档**为当前有效版本；**历史文档**保留用于追溯决策过程。

## 现行文档（最新有效）

| 文档 | 内容 | 更新 |
|---|---|---|
| [training-architecture-overview.md](training-architecture-overview.md) | **系统全景架构与训练实录**（四层架构 / verl / AGS 沙箱 / 数据流 / 实测结果 / 术语表）| 2026-09-20 |
| [pod-ags-communication.md](pod-ags-communication.md) | **Pod ↔ AGS 通信全链路手册**（三层架构 / 一条命令的 7 步生命周期 / 4 组真实数据案例 / 可靠性设计 / 数字账）——训练与测试通用 | 2026-09-21 |
| [ags_image_override.md](ags_image_override.md) | **AGS 镜像覆盖方案**（1 个通用工具服务 N 道题，含全流程实测证据）| 2026-09-18 |
| [../reports/swegym-30b-tier0-r1/README.md](../reports/swegym-30b-tier0-r1/README.md) | **训练完整报告**（沙箱构建 / TKE 部署 / 模型选型 / 超参 / 结果分析）| 2026-09-19 |
| [../reports/swegym-30b-tier0-r1/REFERENCE.md](../reports/swegym-30b-tier0-r1/REFERENCE.md) | 资产引路（权重 / 轨迹 / 数据 / COS 备份位置 + 推理加载示例）| 2026-09-20 |
| [troubleshooting/README.md](troubleshooting/README.md) | **问题复盘归档**（7 篇：运行复盘 / 基础设施 / 沙箱 / 训练引擎 / 数据判分 / Agent 协议 / 工程工具箱）——含症状速查表 | 2026-09-20 |
| [validation/README.md](validation/README.md) | **最终验证阶段计划**（30B base vs base+LoRA pass@1 对比）：4 份 ADR（测试集 / 协议 / 架构 / 判定）+ 术语表——开测前全部锁定 | 2026-09-20 |
| [validation/pass4-test-design-postmortem.md](validation/pass4-test-design-postmortem.md) | **pass@4 测试设计复盘**（协议 / 四轮缺陷链 / 结果有效性评估 / 下轮改进 checklist）+ 结果摘要（负结果如实报告） | 2026-09-21 |

## 历史文档（保留追溯，内容已过时）

| 文档 | 说明 |
|---|---|
| [ags_tool_setup.md](ags_tool_setup.md) | 旧"逐题建工具"方案 —— **已被镜像覆盖方案取代**（文首已标注）|
| [tokyo_gpu_plan.md](tokyo_gpu_plan.md) | 跨区链路规划（§0 时延评估仍有参考价值）|
| [PROJECT_REPORT.md](PROJECT_REPORT.md) | 2026-09-11 阶段汇报（当时指标未达标；后续问题均已解决）|
| [rl-pipeline-report.md](rl-pipeline-report.md) | 2026-09-11 RL 流水线报告（基于 recovery-14b-fullbatch-v4 运行）|
| [PHASE_A_STATUS.md](PHASE_A_STATUS.md) | 2026-09-10 Phase A 冒烟状态 |

## 相关目录

| 目录 | 内容 |
|---|---|
| `reports/` | 训练运行报告（图表 / 指标 CSV / 配置 / 日志）|
| `../artifacts/archive/training-runs/` | **9 次训练/评估全记录归档**（每次独立文件夹 + 时间线总表 + Top 问题与解决方案）|
| `../artifacts/archive/` | 本机归档副本（完整归档，含 LoRA 权重）|
| `../briefing/` | 内部汇报材料（不随仓库发布）|
