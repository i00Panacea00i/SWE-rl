# AGS 沙箱工具创建清单（12 题 × 1 工具，无 API Key 方案）

> 每个工具绑定一个固定镜像（AGS 不支持创建实例时动态指定镜像）。
> 全部工具配置**除镜像地址外完全相同**，逐项创建约 2 分钟/个。
> 12 题中 sympy-11384 为 flaky（仅批量拉起凑规模），有效题 11 道。

## 1. 工具列表（控制台 → AGS → 沙箱工具 → 创建）

| 工具名称 | 镜像地址 |
|---|---|
| `swe-astropy-12057` | `tcr.example.com/swe-mirror/swe-ags:astropy_1776_astropy-12057` |
| `swe-astropy-12907` | `tcr.example.com/swe-mirror/swe-ags:astropy_1776_astropy-12907` **（新增）** |
| `swe-django-10939` | `tcr.example.com/swe-mirror/swe-ags:django_1776_django-10939` |
| `swe-django-11039` | `tcr.example.com/swe-mirror/swe-ags:django_1776_django-11039` |
| `swe-django-12286` | `tcr.example.com/swe-mirror/swe-ags:django_1776_django-12286` **（新增）** |
| `swe-matplotlib-13859` | `tcr.example.com/swe-mirror/swe-ags:matplotlib_1776_matplotlib-13859-r2` **（注意 -r2 修复版）** |
| `swe-requests-1327` | `tcr.example.com/swe-mirror/swe-ags:psf_1776_requests-1327` |
| `swe-pylint-4551` | `tcr.example.com/swe-mirror/swe-ags:pylint-dev_1776_pylint-4551` |
| `swe-scikit-learn-10198` | `tcr.example.com/swe-mirror/swe-ags:scikit-learn_1776_scikit-learn-10198` |
| `swe-sphinx-10021` | `tcr.example.com/swe-mirror/swe-ags:sphinx-doc_1776_sphinx-10021` |
| `swe-sympy-11232` | `tcr.example.com/swe-mirror/swe-ags:sympy_1776_sympy-11232` |
| `swe-sympy-11384` | `tcr.example.com/swe-mirror/swe-ags:sympy_1776_sympy-11384`（flaky，仅批量拉起验证用） |

## 2. 每个工具的配置（缺项即实例创建超时 —— 上个项目踩坑 #3/#5）

| 配置项 | 值 |
|---|---|
| 工具类型 | custom（自定义） |
| **启动命令** | **`/init`**（固定值） |
| **启动参数** | `sleep`、`infinity`（**两个独立输入框，不可合并**） |
| **端口配置** | 名称 `envd`，协议 **TCP**，端口 **49983** |
| **健康检查** | 探针路径 **`/health`**，探针端口 **49983**，就绪超时 30000ms，周期 3000ms，失败阈值 100 |
| CAM 角色 | 具备 TCR 拉取权限的角色（绑定到工具**实际**的 RoleArn，注意后缀） |
| 镜像仓库凭证 | `agc-psle0qp6`（或同企业版实例新建凭证） |
| 网络模式 | **PUBLIC**（Phase A 验证用 SANDBOX 亦可；RL rollout 时 AgentLoop 需可达 envd 49983，建议 PUBLIC 或按平台内网方案） |
| 资源规格 | 1C2G 起（sphinx/tox、sklearn 套件较重） |

## 3. 创建后：预热（避免首次创建拉镜像超时）

API Explorer → `CreatePreCacheImageTask`（Region=ap-singapore，
Image=完整镜像地址，ImageRegistryType=enterprise）→
`DescribePreCacheImageTask` 确认完成。10 个镜像各执行一次。

## 4. 就绪探测（CVM 上）

```bash
cd /root/swe-rl-kit && set -a && source .env && set +a
venv/bin/python sandbox/probe_tools.py   # 10/10 就绪即 OK
```

## 5. 就绪后一键验证

```bash
venv/bin/python sandbox/validate_swe_ags.py --verify-runs 2 --parallel 4 \
    --output-jsonl output/merged/benchmark.jsonl
```

预期：**11/12 validated**（sympy-11384 为 flaky，按 G1 规则留痕剔除）。
注意 `--parallel` 并发不宜过高（每实例会串行创建 baseline+golden×N 个沙箱）。

## 附 1：matplotlib 修复镜像说明

原 `swe-ags:matplotlib_1776_matplotlib-13859` 在 AGS 基底重建时丢失了官方
Dockerfile 中的系统库（`libfreetype6` 等），导致 `from matplotlib import ft2font`
ImportError。修复版 `-r2`（digest
`sha256:66ae79311e19ba3d9c54fc451eaf357655b677e89ef74804d9820cf8c26403f6`）
已叠加补齐并推 TCR，本地双向验证 PASS。

## 附 2：新增两题说明（2026-09-10）

为满足「≥10 题且剔除 flaky 后仍 ≥10」，从 SWE-bench 补充 2 题，按现有配方
（AGS 基座 + 官方 sweb.eval 的 /testbed+conda，见 `sandbox/Dockerfile.swe-ags.tmpl`）
构建并推 TCR，本地双向验证均 PASS：
- `astropy__astropy-12907`（digest `sha256:8e30a7af…d27df5f`）
- `django__django-12286`（digest `sha256:95a1dd00…bbb2ac`）
- 曾试 `django__django-11099`：1/3 F2P 在 base 即通过（数据集标注问题，3 次复现
  一致），已弃用并从 TCR 清单移除（未推送）。
