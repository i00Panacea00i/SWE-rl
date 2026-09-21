# Run 02 · recovery-14b-adapter-v2-warmup（14B 首次）

| 项 | 内容 |
|---|---|
| 日期 | 2026-09-11 |
| 模型 | Qwen2.5-Coder-14B（单卡 L20，LoRA） |
| 步数 | 2 步（warmup 后终止） |
| 结果 | pipeline `status=stopped, fatal_log=true`；判分器 `RuntimeError` |
| 状态 | ❌ 终止——**判分器健壮性缺陷** |

## 目标
升级到 14B（7B 无信号后的第一次模型升级）。

## 遇到的问题与解决方案

### 问题 1：判分器被"坏补丁"击穿 → 整个训练终止
**现象**：模型产出的坏补丁（Django 仓库引入 `SystemCheckError`，框架级启动失败）→
官方 log parser 无法解析非常规输出 → 判分器抛 `RuntimeError` → 流水线 fatal-log
检测**终止整个运行**。

**根因**：判分器把"模型产出坏补丁导致的解析失败"当成了"基础设施故障"来处理——
而在 RL 训练里，坏补丁是**常态**（模型在探索，必然产出大量错误代码）。

**解决方案**（`sandbox/harness.py` + `sandbox/episode.py` 三级降级）：
1. 语法/收集/框架级失败（附"无补丁对照"确认）→
   `failure_kind=candidate_collection_or_import_error`，**记 0 分**；
2. 残余判分异常 → `failure_kind=judge_error`，**降级 0 分样本**；
3. **任何情况不中断训练**。

## 沉淀
判分器的设计原则更新：**"解析失败 = 0 分"而非崩溃**——判分器必须是 RL 循环里
最健壮的组件（它面对的输入天然充满恶意/错误）。

## 产物
- 14B 适配器导出与下载过程记录：`artifacts/recovery/`
  （adapter-export-test-pod、download-*-pod、fsdp-export-monitor 等）
