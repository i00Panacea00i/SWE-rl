# Run 06 · swegym-9b-tier0-r1（Qwen3.5-9B 单卡，未完成）

| 项 | 内容 |
|---|---|
| 日期 | 2026-09-18 |
| 模型 | Qwen3.5-9B——**意外发现是原生多模态**（vision + language 混合） |
| 硬件 | 单卡 L20（44GB） |
| 结果 | 未完成：启动阶段连撞**十余项障碍**，最终战略放弃 |
| 状态 | ❌ 放弃——**模型形态选型失误 + 单卡极限** |

## 目标
7B 能力不足后的中间升级（9B，期望单卡可承载）。

## 遇到的问题与解决方案（十余项，归类记录）

| # | 问题 | 根因 | 解决方案 |
|---|---|---|---|
| 1 | 镜像拉取失败 | 清单里 digest 笔误 | 修正 digest |
| 2 | 启动即数据缺失 | kit 数据不完整（instances + task_specs 未上传全） | 补齐 kit 数据 |
| 3 | 加载报缺文件 | 多模态模型需要 preprocessor 文件 | 从 HF 补齐 |
| 4 | 输出异常 | thinking 模式开启 | `enable_thinking=false` |
| 5 | KV cache 不足（vLLM 起不来） | 原生上下文 262144 → KV 需 8.1GB | `max_model_len=16384` |
| 6 | 权重同步 OOM | vLLM 不释放显存（18.4GB）+ FSDP 全量参数（18GB）≈ 44.4GB 贴线 | `free_cache_engine=True` |
| 7 | `free_cache_engine` 顺序矛盾 | 配置组合互相冲突 | 调整配置组合 |
| 8 | LoRA 导出显存尖峰 | 全量导出缓冲 | 逐单元导出（≤1.2MB/单元） |

## 最终决策与沉淀
- 修复到可运行后遭遇**平台侧工具清空**（09-17 平台变更）+ 多模态模型对推理栈的
  特殊要求 → **战略性放弃，转 30B-MoE + 4 卡方案**（Run 07）。
- **选型教训固化**：选模型前必查 ① `config.json` 的 `architectures` 是否有
  `vision_config`（多模态伪装成语言模型）② vLLM 支持列表 ③ 上下文长度的 KV 代价。

## 产物
- `pod-manifest.json`（本次运行清单）
- 相关排障：`docs/troubleshooting/04-training-engine.md`、`06-agent-protocol.md`
