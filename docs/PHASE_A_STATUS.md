# Phase A 交付状态（沙箱 + 数据 + tracing 冒烟）

> 日期：2026-09-10 ｜ 工作区：`/root/swe-rl-kit`
> 范围：AGS 批量拉起验证 + 数据准备 + harness + tracing 冒烟（训练闭环见 tokyo_gpu_plan.md）

## 已完成

| 项 | 状态 | 证据 |
|---|---|---|
| 12 题元数据（SWE-bench，含 test_patch/F2P/P2P/金标） | ✅ | `data/instances.jsonl` |
| 官方 eval 协议（swe-bench-tasks eval.sh/tests.json） | ✅ | `data/task_specs/` |
| harness（官方 log_parser + F2P/P2P 判分 + 比例奖励） | ✅ | `sandbox/harness.py` |
| 本地双向验证（baseline FAIL + golden PASS） | ✅ **11/12** | `artifacts/local_smoke_final.json`、`local_smoke_new2.json` |
| matplotlib 镜像修复（补 libfreetype6 等，推 TCR `-r2`） | ✅ | digest `sha256:66ae79…403f6` |
| 新增 2 题（astropy-12907 / django-12286，官方镜像搬运+AGS 配方重建） | ✅ | `sandbox/Dockerfile.swe-ags.tmpl` |
| tracing 冒烟（3 步 agent 回路 + reward） | ✅ **逐步 (action, observation, reward, done)，11 题 reward=1.0；sympy-11384 reward=0.0（flaky 佐证）** | `artifacts/traces/*/` |
| verl 训练 parquet（11 题，剔除 flaky） | ✅ | `data/train.parquet` |
| AGS 批量验证驱动（幂等/flock/证据/flaky 闸门） | ✅ 代码就绪 | `sandbox/validate_swe_ags.py` |
| 工具就绪探测 | ✅ 代码就绪 | `sandbox/probe_tools.py` |
| 东京 GPU 训练适配方案 + 部署骨架 | ✅ | `docs/tokyo_gpu_plan.md`、`deploy/`、`configs/` |

## 数据质量结论

- **sympy__sympy-11384：flaky**（`test_pretty_FourierSeries` 在 base 与 golden 下均
  ~50% 翻转；官方 swe-env 镜像同样翻转 → 测试本身非确定，与镜像无关）。
  处置：批量拉起验证仍包含（凑满 10 题），**训练集默认剔除**（`prepare_data.py` 内置）。
- 其余 9 题：baseline 全部 fail_as_expected，golden 全部 pass（本地 docker，与 AGS
  同镜像同协议）。

## 踩坑沉淀（本阶段新增）

1. **官方镜像含构建期未提交修改**（如 sphinx 对 tox.ini 的 `sed 's/pytest/pytest -rA/'`），
   全树 `git checkout base -- .` 会还原它们导致解析全失败 → 每模式必须用全新沙箱，
   禁止 reset 复用；
2. **stdout/stderr 分流破坏标记截取**：pytest 输出走 stdout、`set -x` trace 走 stderr，
   必须 `2>&1` 在沙箱内合并（官方 harness 用 docker logs 时间序合并流）；
3. **AGS 基底重建丢系统库**：matplotlib 缺 `libfreetype.so.6` → 已叠加 `-r2` 修复镜像；
4. **git dubious-ownership 静默失败**：`git apply` 前必须 `git config --global --add
   safe.directory /testbed` 且驱动必须检查非 eval 命令退出码。

## 阻塞项（需控制台操作，无 API Key 替代方案）

1. 按 `docs/ags_tool_setup.md` 创建 10 个 AGS 沙箱工具（~2 分钟/个）；
2. 每个镜像 `CreatePreCacheImageTask` 预热（API Explorer）；
3. 完成后依次运行：

```bash
cd /root/swe-rl-kit && set -a && source .env && set +a
venv/bin/python sandbox/probe_tools.py                       # 12/12 就绪
venv/bin/python sandbox/validate_swe_ags.py --verify-runs 2 --parallel 4  # 预期 11/12 validated
venv/bin/python sandbox/agent_smoke.py --runtime ags --instance django__django-10939
venv/bin/python data/prepare_data.py --input output/merged/benchmark.jsonl
```

## 附：工具就绪前探测基线（2026-09-10）

`probe_tools.py` 当前输出：工具 0/12（待控制台创建）、TCR tag 12/12 OK
（含 matplotlib `-r2` 修复版与 2 个新增题）。API Key 与数据面连通性已验证。
