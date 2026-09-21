# Pod ↔ AGS 通信全链路：测试与训练通用手册

> **读者指引**：管理者看 §0（60 秒速览）；工程师看 §1–§6（含真实数据案例）。
> **素材来源**：测试侧 400 条轨迹（`artifacts/archive/pass4-eval-20260921/`）与
> 训练侧 3384 份命令证据（CFS `traces/swegym-30b-tier0-r1/train/`）——全部为
> 2026-09-20/21 真实运行数据，未做修饰。

---

## 0. 60 秒速览（给管理者）

**类比**：AGS（Agent Sandbox）是我们的**云端考试中心**——每个考生（模型）在独立
考位（沙箱）里做题；Pod（评估/训练程序）是**阅卷老师**，通过两条通道与考试中心打交道：
一条用来"开考位/退考位"（控制面），一条用来"传题目、收答卷"（数据面）。

**一次"递作业"的旅程**（真实延迟 0.1–30 秒）：

```
模型写出一条 bash 命令
   ↓ 老师加"保护套"（防挂起、防超长输出）
   ↓ HTTPS 传到考试中心（东京→新加坡）
   ↓ 考位里执行（Debian 13 环境，/testbed 仓库）
   ↓ 结果原路返回（stdout/stderr + 退出码）
模型读到结果，决定下一步
```

**三个关键数字**：
- 单条命令往返 **0.1–30 秒**（本手册案例实测 0.12–0.59 秒）
- 每条轨迹（episode）最多 **12 轮**"写命令→收结果"
- 平台上限 **100 个沙箱**同时在线（我们按批调度）

**为什么这样设计**：① 安全——模型代码只在隔离沙箱里跑，碰不到我们任何生产系统；
② 公平——训练与测试用**同一套**通道和判分器；③ 可审计——每条命令、每个回传都有存档。

---

## 1. 三层通信架构（技术总览）

### 1.1 控制面：创建/销毁沙箱（腾讯云 AGS API）

| 项 | 内容 |
|---|---|
| 协议 | HTTPS + 腾讯云 SDK（`tencentcloud.ags.v20250920`） |
| 凭证 | oauth 型凭证（挂载在 Pod 的 `/root/.tccli` secret），**refreshToken 自动续期** |
| 关键调用 | `StartSandboxInstance`（建）→ `DescribeSandboxInstanceList`（轮询至 RUNNING）→ `StopSandboxInstance`（清） |
| 镜像覆盖 | 只创建"通用工具 `swe-ags`"，把**题目专属镜像**作为参数传入（1 个工具服务 N 道题） |
| 频率 | 每条 episode 1 次创建 + 1 次销毁；就绪（镜像已预热时）约 5 秒 |

### 1.2 数据面：执行命令/传文件（e2b 协议）

| 项 | 内容 |
|---|---|
| 协议 | HTTPS + `e2b_code_interpreter` SDK |
| 凭证 | `E2B_API_KEY`（Pod 环境变量）+ 域 `E2B_DOMAIN=ap-singapore.tencentags.com` |
| 关键调用 | `Sandbox.connect(id)` → `sb.commands.run(bash)` / `sb.files.read·write` |
| 对端 | 沙箱内的 **envd**（HTTP 服务）→ 落到沙箱的 bash（`/testbed` + miniconda 环境） |
| 网络路径 | Pod（东京 TKE）→ 公网 HTTPS → AGS（新加坡）；16 路并发掩盖跨境延迟 |

### 1.3 判分面：独立沙箱（隔离保证）

判分在**全新沙箱**执行：模型改完代码 → 导出补丁 → 在干净考位重放补丁 →
跑官方测试 → 解析通过数。模型全程看不到判分过程与标准答案。

### 1.4 训练 vs 测试：同一管道、不同触发

| | 训练（rollout） | 测试（评估） |
|---|---|---|
| 触发 | 每步 8 题 × 4 rollout | 一次性 40 题 × n |
| 代码路径 | `verl_plugin/swe_agent_loop.py` → `EpisodeSession` | `controller/eval_driver.py` → `EpisodeSession` |
| 沙箱通道 | **完全相同**（同一 `sandbox/ags_instance.py`） | **完全相同** |
| 落盘 | `traces/<run>/train/step-N/.../agent/execution.json` | `traces/<run>/vllm[-pass4]/<iid>__sK/execution.json` |

---

## 2. 一条命令的完整生命周期（7 步 · 真实数据）

### 2.1 模型产出

真实案例（测试侧 `iterative__dvc-4623__s0`，reward=1.0 的成功轨迹）——模型输出
（含思考 + 命令块）：

````
Looking at the test structure, I need to make sure that the allow_agent parameter is
properly read from config and passed to paramiko. Let me examine what exact changes
are needed by looking at the failing tests more closely:

```bash
python -m pytest -rA --no-header -p no:cacheprovider -p no:pretty -p no:snail \
  'tests/unit/remote/ssh/test_ssh.py::test_ssh_allow_agent[config3-False]' -v
```

Let me directly modify the SSH tree implementation to add the allow_agent parameter support:

```bash
sed -i '/ask_password = params.get("ask_password", False)/a\        self.allow_agent = ...
````

> 解析器（`parse_action`）会从混合文本中提取最后一个 bash 代码块为可执行命令
> （宽容解析，见 `troubleshooting/06`）。

### 2.2 包装（Pod 侧，`sandbox/episode.py` 的 5 层防护）

模型的原始命令**不会直接执行**，先被包上 5 层：

| 层 | 作用 | 真实片段 |
|---|---|---|
| ① PATH 注入 | 保证 conda 环境 | `export PATH=/opt/miniconda3/envs/testbed/bin:...` |
| ② 语法预检 | 不完整命令不执行 | `bash -n -c <cmd>` 失败即返回"not executed" |
| ③ 超时双保险 | 防挂起 | `timeout -k 5s 120s bash -lc <cmd>` |
| ④ 输出截断（drain） | 防超大输出撑爆回传 | 头 25% + 尾 75% 保留（上限 `MAX_OUTPUT_BYTES`） |
| ⑤ 目录锚定 | 固定工作目录 | `cd /testbed \|\| exit 125` |

**真实还原**（同一命令经包装后的实际结构——各层参数均取自真实配置）：

```
cd /testbed || exit 125                    ← ⑤ 目录锚定
 ; bash -n -c '<原始命令>'                  ← ② 语法预检（不合法 → exit 2，不执行）
 ; timeout -k 5s 120s bash -lc '<命令>'    ← ③ 超时双保险（cmd-timeout=120s）
 ; python -c '<drain: cap=32768>'          ← ④ 输出截断（MAX_OUTPUT_BYTES=32768）
 ; exit ${PIPESTATUS[0]}                    ← 退出码透传（drain 不吞真值）
```

> 完整单行命令（含嵌套引号转义，长度约为原始命令的 5-8 倍）见
> `sandbox/episode.py` 的 `EpisodeSession.run()`——**语法预检拦截的真实案例见 §2.4 证据集②**。

### 2.3 传输：完整链路与分段实测

`sb.commands.run(wrapped, user="root", timeout=140)` → HTTPS → AGS 网关 → 沙箱 envd → bash。

| 分段 | 实测（样本轨迹 `moto-5737__s1`，16 条命令） | 说明 |
|---|---|---|
| 沙箱内执行 | **0.10 – 2.50 s** | `duration_s` 字段——纯执行耗时（不含网络） |
| 网络往返 | ~0.3–1 s | 东京↔新加坡跨境 HTTPS；16 路并发掩盖 |
| 大输出命令 | 0.26 s（cat 32KB 文件） | 输出经 drain 截断后回传 |

沙箱环境（真实 `fingerprint` 字段，创建时采集并校验）：
```
Linux ee41841b 6.6.69-cube.pvm.guest.005.x … x86_64 GNU/Linux
Debian GNU/Linux 13 (trixie)
仓库位置：/testbed（git 仓库，镜像 HEAD 与 base_commit 校验通过后才开始）
```

### 2.4 沙箱内执行：数据可得性 + 三组真实证据

**首先回答一个关键问题：沙箱内的数据能拿到哪些？**

| 数据 | 可得性 | 载体 | 说明 |
|---|---|---|---|
| 命令 stdout / stderr | ✅ 完整 | `execution.json` | 经 drain 截断（上限 32768B） |
| 退出码（真值） | ✅ 完整 | `execution.json` | PIPESTATUS 透传，不吞码 |
| 每条命令耗时 | ✅ 完整 | `execution.json` | 沙箱内计时（毫秒级） |
| **判分期完整日志** | ✅ 完整 | **`test.log`** | **沙箱内真实日志**（官方测试输出，未截断） |
| 沙箱系统指纹 | ✅ 创建时采集 | `fingerprint` | 内核/发行版（防跑错镜像） |
| envd / 平台内部日志 | ❌ 不开放 | — | AGS 平台侧，无导出 API |

**证据集 ① · 一条完整轨迹的全部 16 条命令**（`moto-5737__s1`——真实的"做题故事"）：

```
[ 1] exit=0  0.570s  trusted  git rev-parse HEAD              → 4ec74854...
[ 2] exit=0  0.123s  trusted  uname -a && cat /etc/os-release → Debian 13 指纹
[ 3] exit=0  0.124s  trusted  git apply -v test patch         → Applied cleanly
[ 4] exit=0  0.516s  trusted  git add -A && write-tree        → 5f6811d3...（快照）
────── 以下为模型命令（trusted=false）──────
[ 5] exit=1  2.502s  python -m pytest ...（首跑失败——探索开始）
[ 6] exit=0  0.174s  cat tests/test_cloudfront/test_cloudfront.py
[ 7] exit=0  0.124s  grep -n -A 50 "def update_distribution" moto/cloudfront/models.py
[ 8] exit=0  0.121s  grep -n -A 20 -B 5 "class.*DistributionConfig" ...
[ 9] exit=0  0.179s  grep -n -A 150 "class DistributionConfig" ...
[10] exit=2  0.103s  散文("But when we create a new DistributionConfig...") → 预检拦截
[11] exit=0  0.127s  sed -i '329i\...'（尝试插入代码）
[12] exit=1  1.008s  pytest（仍失败）
[13] exit=0  0.123s  sed -i '325,335d'（回退删除）
[14] exit=4  0.754s  pytest（收集错误：0 items / 2 errors）
[15] exit=0  0.125s  sed -i '320,340d'
[16] exit=4  0.832s  pytest（仍失败）
```

**证据集 ② · `exit_code` 全谱**（1314 条命令的实测分布）：

| 码 | 数量 | 占比 | 真实样本（命令 → 回传摘录） | 语义 |
|---|---|---|---|---|
| 0 | 1246 | 94.8% | `cat /testbed/mypy/checkstrformat.py` → 32803B 源码 | 成功 |
| 1 | 39 | 3.0% | `pytest ...test_plots` → "…FAILED [ 33%]…" | **正常失败反馈**（非通信故障） |
| 4 | 13 | 1.0% | `pytest ...test_gc` → "collected 0 items / 2 errors" | pytest 收集失败 |
| 2 | 11 | 0.8% | 散文含未闭合引号 → "Incomplete/invalid shell action; **not executed**" | **语法预检拦截** |
| 127 | 5 | 0.4% | 散文（语法合法）→ "bash: Looking: **command not found**" | 散文被执行 |

**exit=2 vs exit=127 对照**（同根因：模型只输出思考、没给命令块——两种命运）：

```
散文含未闭合引号  → bash -n 预检发现 → exit 2（不执行）——防护生效
散文语法合法      → 通过预检 → bash 执行 → exit 127（command not found）
                   → 宽容解析兜底为一次"无效轮次"
```

**证据集 ③ · 输出截断实证**（drain 机制的上限与真实命中）：

```
drain 上限（代码常量）: MAX_OUTPUT_BYTES = 32_768
实测最大 stdout       : 32_803 B——三条命令精确命中（32768 + 截断标记偏移）
截断格式              : 头 8 KB + "\n[output truncated; head and tail]\n" + 尾 24 KB
全量 stdout 总计      : 1.0 MB / 1314 条命令（不截断将撑爆上下文与回传带宽）
```

### 2.5 回传（stdout/stderr + 退出码）——真实数据

同一案例下一轮，模型执行的命令返回（AGS 回传原文，262 字符）：

```
exit_code=0
/testbed/dvc/tree/ssh/__init__.py
/testbed/dvc/tree/ssh/connection.py
/testbed/tests/unit/remote/ssh/__init__.py
/testbed/tests/unit/remote/ssh/test_connection.py
/testbed/tests/unit/remote/ssh/test_pool.py
/testbed/tests/unit/remote/ssh/test_ssh.py
```

**字段语义**：`exit_code` 来自 `PIPESTATUS` 的真值（drain 脚本不吞退出码）；
stdout/stderr 合并回传；回传体即模型的"观察"（observation）。

### 2.5b 判分期沙箱日志（`test.log`）——"沙箱内 log"的完整样貌

判分在**独立沙箱**执行，其完整输出落盘为 `test.log`（**未截断**，约 3.5KB/条，
全部 320 条评估轨迹各一份）。真实案例（dvc-4623）：

头部：
```
Checking patch tests/unit/remote/ssh/test_ssh.py...
Applied patch tests/unit/remote/ssh/test_ssh.py cleanly.
SWE_SOURCE_IMPORT_OK /testbed/dvc/__init__.py

>>>>> Start Test Output
============================= test session starts ==============================
collected 28 items
tests/unit/remote/ssh/test_ssh.py ............................ [100%]
```

尾部：
```
============================== 28 passed in 0.49s ==============================
>>>>> End Test Output
SWE_SUITE_EXIT=0
```

> 这就是"沙箱内 log"的最完整形态：从补丁应用到官方测试运行的全程输出——
> 判分脚本重定向到 `/tmp/swe-eval.log` 后**整份取回**（`sb.files.read`）落盘。
> 归档：`artifacts/archive/pass4-eval-20260921/`（320 份）。

### 2.6 观察截断（512 token）

回传体按 `observation_tokens=512` 截断后才放进对话——防止单次输出（如跑完整测试
套件的几百行日志）挤爆上下文。与训练侧 `configs/swe_agent.yaml` 的 `512` 完全一致。

### 2.7 证据落盘（`execution.json`）——可审计

每条命令在 Pod 侧同步记录（即使进程崩溃前也已落盘）：

```json
{
  "time": 1789723604.36,
  "command": "find /testbed -name \"patches.py\" -type f",
  "exit_code": 0,
  "stdout": "/testbed/conan/tools/files/patches.py\n",
  "stderr": "",
  "duration_s": 0.133,
  "trusted": false
}
```

| 字段 | 含义 |
|---|---|
| `command` | 模型产出的原始命令（未包装） |
| `exit_code` | 0=成功；1=命令失败；2=格式拒绝；124=超时；125=管道/环境错误 |
| `duration_s` | **沙箱内**执行耗时（不含网络往返） |
| `trusted` | `false`=模型命令；`true`=框架内部命令（校验/快照/判分） |

---

## 3. 真实数据案例集

### 案例 A · 测试侧一轮完整交互（成功题 dvc-4623）

| 轮 | 角色 | 内容（节选） | 长度 |
|---|---|---|---|
| 2 | assistant | 思考 + `python -m pytest ...test_ssh_allow_agent...` | 7531 字 |
| 3 | user（AGS 回传） | `exit_code=0` + 6 个文件路径 | 262 字 |
| … | … | 共 9 轮 | |
| 判分 | — | reward=1.0, resolved=True | — |

### 案例 B · 训练侧命令序列（conan-14177，沙箱 `g3mvnjzyf7gaqn6nf5raod3j7mfahqwkhf6jcjdm`）

框架内部命令（`trusted: true`）——体现"创建后先自检"：

| 命令 | 退出码 | 真实输出 | 耗时 |
|---|---|---|---|
| `git rev-parse HEAD` | 0 | `b43eb83956f053a47cc3897cfdd57b9da13a16e6` | 0.515s |
| `uname -a && cat /etc/os-release` | 0 | Debian 13 指纹 | 0.122s |
| `git apply -v /tmp/swe-test.patch` | 0 | `Applied patch conans/test/... cleanly.` | 0.119s |
| `cp .git/index … && git write-tree` | 0 | `b0bdf4ddba43b98bb7b4651fe2197251ebeac192` | 0.296s |

模型命令（`trusted: false`）——观察到的内容与回传机制：

| 命令 | 退出码 | 真实输出 | 耗时 |
|---|---|---|---|
| `find /testbed -name "patches.py" -type f` | 0 | `/testbed/conan/tools/files/patches.py` | 0.133s |
| `cat /testbed/conan/tools/files/patches.py` | 0 | 源码全文（被 512-token 截断后给模型） | — |

### 案例 C · 判分链路（dvc-4623，全真实）

```
① 导出补丁     candidate.patch（模型 9 轮工作的净产出，591 字节）
② 新沙箱重放   git apply --check → git apply               exit=0
③ 执行官方判分 bash /tmp/swe-eval.sh > /tmp/swe-eval.log    exit=0
④ 解析测试日志 28 个用例全部解析
⑤ 判定         reward=1.0 / resolved=True / suite_exit=0
```

判分器真实输出（`test.log` 尾部）：

```
PASSED tests/unit/remote/ssh/test_ssh.py::test_ssh_port[config0-2222]
============================== 28 passed in 0.49s ==============================

>>>>> End Test Output
SWE_SUITE_EXIT=0
```

### 案例 D · 非零退出的语义（模型看到的"失败"）

真实案例（getmoto__moto-5737）：模型跑自测得到 `exit_code=1`
（`python -m pytest ...`，用例失败）——**这不是通信故障**，而是模型收到的正常反馈：
"你的改动没通过测试"。语义表：

| exit_code | 含义 | 模型该如何理解 |
|---|---|---|
| 0 | 成功 | 继续 |
| 1 | 命令执行了但失败（测试挂/断言错） | 修改代码重试 |
| 2 | 命令未执行（语法不完整，被预检拦截） | 重新发出完整命令 |
| 124 | 超时（120s 上限） | 命令太重，换更轻的验证方式 |
| 125 | 管道/环境异常（罕见） | 重试或换命令 |

---

## 4. 可靠性设计（为什么长跑 50 步 / 5 小时不断线）

| 机制 | 实现 | 解决什么问题 |
|---|---|---|
| 凭证自动续期 | oauth refreshToken（`ags_instance.py` 内置续期 + 安全窗口） | 长跑期间凭证过期 |
| 三层超时 | 命令 120s / 沙箱 TTL 1800s / 就绪等待 90s | 挂起命令、僵尸沙箱、创建卡死 |
| 输出保护 | drain 截断（头+尾保留） | 数百行日志撑爆回传与上下文 |
| 配额调度 | 平台上限 100；分批（每批 80）+ 建前探针 | 超限失败（曾发生：160 超限截断 60 个） |
| 镜像预热 | `CreatePreCacheImageTask`（121 题全部预热） | 冷启动从分钟级降到 ~5 秒 |
| 双重校验 | 沙箱 HEAD 必须等于实例 `base_commit`（或仅多 1 个构建提交） | 防止跑错镜像出假结果 |
| 证据链 | 命令级 `execution.json` + 判分 `test.log` + 补丁 sha256 | 事后审计/复现 |

---

## 5. 数字账（成本与规模）

| 规模单位 | 通信操作 | 实测 |
|---|---|---|
| 1 条命令 | 1 次 HTTPS 往返 + 沙箱内执行 | 0.12–0.59s（本手册案例）＋跨境网络开销 |
| 1 条轨迹（episode） | 1 次创建 + ≤12 轮命令 + 1 次销毁 | 25–40 分钟（含模型生成时间） |
| 1 个批次（80 轨迹） | 80 沙箱并发（16 并发执行命令） | ~30 分钟（pass@4 实测） |
| 训练全程（50 步） | 20 题 × 4 rollout × 50 步 ≈ **4000 次沙箱生命周期** | 3384 份命令证据已归档 |
| 测试全程（pass@4） | 320 轨迹（base+lora） | 4 批 × 30 分钟 |

---

## 6. 术语表（管理者版）

| 术语 | 一句话解释 |
|---|---|
| Pod | 我们在云上跑训练/评估的程序容器（"阅卷老师"） |
| AGS / 沙箱 | 腾讯云 Agent Sandbox——隔离的云端做题环境（"考位"） |
| envd | 沙箱内部的通信服务（接收命令、执行、回传） |
| e2b | 沙箱通信协议标准（AGS 兼容实现） |
| episode | 一次完整"做题过程"（最多 12 轮命令交互） |
| rollout | 训练中让模型对同一题做多次尝试（如 4 次） |
| pass@4 | 同一题 4 次尝试中至少成功 1 次（衡量"会做但不稳"） |
| trusted 标记 | 区分"模型命令"与"框架内部命令"的审计字段 |
| 镜像覆盖 | 一个通用沙箱工具 + 按题切换镜像（配额从 28 个工具降到 1 个） |
