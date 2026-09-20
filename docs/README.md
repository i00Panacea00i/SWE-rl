# 文档索引（docs/）

> 本页是项目文档地图。**现行文档**为当前有效版本；**历史文档**保留用于追溯决策过程。

## 现行文档（最新有效）

| 文档 | 内容 | 更新 |
|---|---|---|
| [training-architecture-overview.md](training-architecture-overview.md) | **系统全景架构与训练实录**（四层架构 / verl / AGS 沙箱 / 数据流 / 实测结果 / 术语表）| 2026-09-20 |
| [ags_image_override.md](ags_image_override.md) | **AGS 镜像覆盖方案**（1 个通用工具服务 N 道题，含全流程实测证据）| 2026-09-18 |
| [../reports/swegym-30b-tier0-r1/README.md](../reports/swegym-30b-tier0-r1/README.md) | **训练完整报告**（沙箱构建 / TKE 部署 / 模型选型 / 超参 / 结果分析）| 2026-09-19 |
| [../reports/swegym-30b-tier0-r1/REFERENCE.md](../reports/swegym-30b-tier0-r1/REFERENCE.md) | 资产引路（权重 / 轨迹 / 数据 / COS 备份位置 + 推理加载示例）| 2026-09-20 |

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
| `../artifacts/archive/` | 本机归档副本（完整归档，含 LoRA 权重）|
| `../briefing/` | 内部汇报材料（不随仓库发布）|
