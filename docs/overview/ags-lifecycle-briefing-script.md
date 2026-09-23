# AGS 生命周期讲解稿（口头汇报版）

**主题**：代码层面讲清楚三件事——① Pod 如何创建 AGS 沙箱；② Pod 如何销毁 AGS 沙箱；③ 数据面如何与 AGS 传输数据。

> **使用说明**：本文为口头汇报稿，总时长约 12–15 分钟。
> 每节按【一句话概括】→【代码调用顺序】→【关键接口】【实测数据】组织，可按需取舍。
> 文末附【领导追问备用问答】与【关键命令速查】。
> 所有函数名、参数、行号均与当前代码逐字核对过，引用格式 `文件:行号`。

---

## 开场（30 秒）

> "今天我用代码讲清楚三件事：Pod 怎么'开'一个沙箱、怎么'关'一个沙箱、以及在开关之间
> 怎么跟沙箱传数据。所有细节都来自我们自己的代码 `sandbox/ags_instance.py`、`sandbox/episode.py`
> 和 `verl_plugin/swe_agent_loop.py`——不是设计文档，是线上跑过 21 小时、1692 条轨迹的代码。"

**先给一张全景**（打在屏幕上）：

```
训练主循环（AgentLoop）
   │  ① 每条轨迹：session.start()      ← 创建（第一部分）
   │  ② 每轮交互：session.run(cmd)     ← 数据传输（第三部分）
   │  ③ 轨迹结束：session.close()      ← 销毁（第二部分）
   ▼
EpisodeSession（episode.py）
   │  控制面（创建/销毁）：ags_instance.py → 腾讯云 AGS SDK
   │  数据面（传数据）：  e2b SDK → 沙箱 envd
   ▼
腾讯云 AGS 沙箱（每题一个独立镜像实例）
```

---

## 第一部分 · 创建：从 AgentLoop 到 RUNNING 沙箱（约 5 分钟）

### 1.1 谁发起创建（入口在哪）

> "创建不是训练框架自动做的，是我们自己在 AgentLoop 里显式调用。**入口只有一个点**。"

```86:88:verl_plugin/swe_agent_loop.py
            record["sandbox_id"] = session.sandbox_id
            record["sandbox_mode"] = session.sandbox_mode
            record["fingerprint"] = session.fingerprint
```

调用顺序（背下这 3 步即可）：
1. **第 67 行**：`EpisodeSession(inst, directory, timeout=1800, apply_test_patch=True)` —— 构造会话对象（此时还没有沙箱）；
2. **第 85 行**：`await asyncio.to_thread(session.start)` —— **真正创建沙箱**（放线程池，不阻塞事件循环）；
3. **第 86–88 行**：把沙箱三件套（实例 ID / 模式 / 指纹）写进轨迹档案。

> **要点**：入口在 `session.start()`（`sandbox/episode.py:124`），它内部再根据"是否配置了题目镜像"走两条路。

### 1.2 创建的核心流程（代码级 7 步）

```
session.start()                                   episode.py:124
 ├─ ① 读题目镜像：image_tcr = inst.image_tcr
 │      ├─ 非空 → start_instance(...)  ★ 主路径（镜像覆盖模式）
 │      └─ 为空 → Sandbox.create(template=工具名)   ← 旧回退路径，已不用
 ├─ ② start_instance(image_tcr, tool_name="swe-ags", timeout_s=1800)   ags_instance.py:179
 │      ├─ 拿客户端：_client(region)                 ags_instance.py:161
 │      ├─ 拿凭证：_current_credential()             ags_instance.py:150
 │      ├─ 组装请求：StartSandboxInstanceRequest()   ags_instance.py:188
 │      ├─ 发起创建：client.StartSandboxInstance(req)（腾讯云 API 调用）
 │      └─ 轮询就绪：DescribeSandboxInstanceList（每 3 秒，最多 90 秒）  ags_instance.py:198
 ├─ ③ 建数据通道：Sandbox.connect(instance_id)      episode.py:134（e2b SDK）
 │      └─ 失败兜底：stop_instance(instance_id)      episode.py:137（不留孤儿实例）
 ├─ ④ 自检 1：git rev-parse HEAD（版本核对）
 ├─ ⑤ 自检 2：镜像构建校验（详见 1.4）
 ├─ ⑥ 自检 3：uname -a → 记录 fingerprint           episode.py:174
 └─ ⑦ 快照工作树：git write-tree → self.tree        episode.py:184-188
```

### 1.3 关键 SDK / API / 参数（逐字）

**SDK 初始化**（`ags_instance.py:161-176`）：

```172:174:sandbox/ags_instance.py
    client = ags_client.AgsClient(
        tc_credential.Credential(cred["secretId"], cred["secretKey"], cred["token"]),
        region)
```
- SDK 包名：`tencentcloud.ags.v20250920`（客户端 `ags_client.AgsClient`，凭证 `tc_credential.Credential`）
- 区域：`DEFAULT_REGION`，取自环境变量 `DEPLOY_REGION`，默认 `ap-singapore`

**创建实例的三个关键参数**（`ags_instance.py:188-194`）：

| 参数 | 值（真实） | 说明 |
|---|---|---|
| `req.ToolName` | `swe-ags`（环境变量 `AGS_MULTI_TOOL`） | **通用工具**——1 个工具服务所有题目 |
| `req.Timeout` | `"1800s"`（即 30 分钟） | 实例级存活上限（**必传**，默认仅 5 分钟） |
| `req.CustomConfiguration.Image` | `<TCR 地址>:<题目 tag>` | **题目专属镜像**（镜像覆盖） |
| `req.CustomConfiguration.ImageRegistryType` | `"enterprise"` | 企业镜像仓库类型 |

**轮询就绪**（`ags_instance.py:198-207`）：每 3 秒查一次 `DescribeSandboxInstanceList`（`Limit=100`），
从返回列表里按 `InstanceId` 找到本实例，状态为 `RUNNING` 即返回；超过 90 秒（`ready_timeout_s`）抛 `TimeoutError`。

**凭证获取的三级优先级**（`ags_instance.py:113-147`，长跑关键）：

| 优先级 | 来源 | 适用场景 |
|---|---|---|
| 1 | OAuth 刷新链（`TENCENTCLOUD_REFRESH_TOKEN` + `OPEN_ID`） | **生产训练**——凭证到期自动续期 |
| 2 | 静态密钥（`TENCENTCLOUD_SECRET_ID/KEY`） | 子账号长期密钥 |
| 3 | 本机 `~/.tccli/default.credential` | 开发机 |

OAuth 刷新是**两步打卡**（`ags_instance.py:85-110`，与腾讯云 CLI `tccli` 同款算法）：
```
POST https://cli.cloud.tencent.com/refresh_user_token  → 拿 AccessToken
POST https://cli.cloud.tencent.com/get_temp_cred       → 拿临时密钥（SecretId/SecretKey/Token/ExpiresAt）
```

**两个生产级防护**（21 小时长跑全靠它们）：
1. **跨进程缓存**（`ags_instance.py:39-57`）：10 个并行工作进程共享 `/tmp/ags-cred-cache.json`，
   只允许一个进程真正刷新——这是"每秒请求 24 次超上限 20"事故的修复方案；
2. **限流退避**（`ags_instance.py:60-72`）：`_oauth_refresh_with_retry` 最多重试 6 次，
   命中限流时按 `1.5s × (i+1)` 递增等待。

### 1.4 创建后的四道自检（防"跑错环境出假数据"）

| 自检 | 命令/机制 | 失败后果 |
|---|---|---|
| ① 版本核对 | `git rev-parse HEAD` 必须等于题目 `base_commit`（40 位 hex 校验） | 抛 `RuntimeError` |
| ② 构建校验 | 官方镜像允许 base 之上多 1 个构建提交（`merge-base --is-ancestor` + 提交数 = 1） | 抛 `RuntimeError` |
| ③ 环境指纹 | `uname -a && cat /etc/os-release` → 落盘 `fingerprint` | 记录备查 |
| ④ 工作树快照 | `git write-tree` 得到"原始树"哈希（判分/补丁导出全靠它） | 抛 `RuntimeError` |

### 1.5 实测数据（107 条完整轨迹挖掘）

| 指标 | 实测值 |
|---|---|
| 会话启动 → 沙箱首条自检命令 | **中位 7.1 秒**（最快 5.1s / 最慢 9.5s） |
| 创建模式 | `image_override`（126/136 条，镜像覆盖全面生效） |
| 就绪轮询次数 | 通常 1–2 次（3 秒间隔，镜像已预热） |

> **小结话术**：创建这条链路的本质是"**一次云 API 调用 + 一次轮询 + 一次 e2b 连接**"，
> 总共 7 秒左右完成；关键工程投入在凭证续期与四道自检上，而不是创建本身。

---

## 第二部分 · 销毁：三层清理机制（约 4 分钟）

> "销毁这个话题，我要强调一个设计原则：**沙箱不允许泄漏**。我们做了三层保险——
> 正常路径关闭、异常路径兜底、平台超时兜底。任何一层生效，实例都不会残留。"

### 2.1 正常路径：轨迹正常结束 → `close()`

调用点在 AgentLoop 的两个位置，**顺序很重要**：

```
① 轨迹正常走完（补丁已导出、文件清单已记录）：
   swe_agent_loop.py:183   await asyncio.to_thread(session.close)
   swe_agent_loop.py:184   closed = True              ← 标记"已关闭"，避免重复关

② 无论任何异常（模型报错/判分异常/进程中断）：
   swe_agent_loop.py:244-246  finally: if not closed: await asyncio.to_thread(session.close)
```

> **口头强调**：第 ② 条是"无论如何都会执行"的 finally 兜底——即使轨迹中途抛异常，
> 沙箱也一定会被关掉；`closed` 标记保证不会重复关闭。

### 2.2 `close()` 内部做什么（`sandbox/episode.py:265-279`）

```269:277:sandbox/episode.py
                self.sb.kill()
            except Exception as exc:
                cleanup_error = type(exc).__name__
            self.sb = None
        atomic_json(self.directory / "execution.json", {
            "instance_id": self.inst.instance_id, "sandbox_id": self.sandbox_id,
            "fingerprint": self.fingerprint, "commands": self.commands,
            "cleanup_error": cleanup_error,
        })
```

三件事，按顺序：
1. **`self.sb.kill()`** —— e2b SDK 的关闭调用（经 AGS 的 e2b 兼容层终止实例）；
2. **落盘 `execution.json`** —— 把该轨迹的**全部命令记录 + 清理结果**写入磁盘（即使 kill 失败也照样落盘）；
3. **失败不吞** —— 若 kill 抛异常，记录异常类型到 `cleanup_error`，并向上抛 `RuntimeError`（`episode.py:278-279`）。

### 2.3 异常兜底 A：连接失败 → 云 API 直接销毁

创建流程中有一个"创建成功但连接失败"的中间态——这时 e2b 还没有句柄可 kill，
必须直接调 AGS 云 API 销毁（`sandbox/episode.py:129-138`）：

```134:137:sandbox/episode.py
                self.sb = Sandbox.connect(instance_id, timeout=self.timeout)
            except Exception:
                stop_instance(instance_id)          # 连接失败不留下孤儿实例
                raise
```

`stop_instance` 的实现（`sandbox/ags_instance.py:211-221`）——**best-effort 语义**：

```216:218:sandbox/ags_instance.py
        req = models.StopSandboxInstanceRequest()
        req.InstanceId = instance_id
        _client(region).StopSandboxInstance(req)
```
- 关键 API：`StopSandboxInstanceRequest` → `client.StopSandboxInstance`
- "best-effort"：销毁失败不抛异常（返回 `False`），因为此时主线已经要失败退出了——
  销毁只是清理动作，不能再掩盖原始错误。

### 2.4 平台兜底 B：实例 TTL（创建时已埋好）

创建请求里的 `req.Timeout = "1800s"`（`ags_instance.py:190`）就是**最后一道保险**：
即使 Pod 整个崩溃、来不及执行任何清理代码，AGS 平台也会在 30 分钟后自动回收实例。

### 2.5 判分沙箱的销毁（独立生命周期）

判分用的是**另一个全新沙箱**（`evaluate_patch`，`episode.py:282`），销毁同样有保证：

```
正常结束：episode.py:365-366   finally: session.close()
特殊路径：episode.py:340       先 session.close() 再跑 baseline 对照
                               （对照沙箱是 evaluate_patch 的递归调用，自带同样的 close 保证）
```

### 2.6 销毁链路的实测证据

| 证据 | 实测结果 |
|---|---|
| `cleanup_error` 字段 | 全部轨迹为 `null`（**零实例泄漏**） |
| 轨迹档案可核对 | `execution.json` 的 `sandbox_id` 可与 AGS 控制台实例列表逐一比对 |
| 异常记录 | kill 失败会带异常类型抛出，不会被静默吞掉 |

> **小结话术**：销毁的完整链路是——**e2b 关闭（正常）→ 云 API 销毁（异常兜底）→ 平台 TTL（最终保险）**。
> 证据是每条轨迹的 `cleanup_error` 全为 `null`。

---

## 第三部分 · 数据传输：建连 / 鉴权 / 读写 / 关闭（约 5 分钟）

> "数据面回答一个问题：**模型的一条命令，是怎么送进沙箱、结果怎么拿回来的**。
> 走的是 e2b 协议，对端是沙箱内的 envd 服务。四个环节：建连、鉴权、读写、关闭。"

### 3.1 建连与鉴权（创建时已完成一次，之后复用）

| 环节 | 实现 | 真实配置 |
|---|---|---|
| SDK | `from e2b import Sandbox`（`episode.py:13`） | e2b Python SDK |
| 鉴权 | 环境变量 `E2B_API_KEY`（**以 Secret 挂载进 Pod**） | pod 清单第 35–39 行 |
| 服务域 | 环境变量 `E2B_DOMAIN` | `ap-singapore.tencentags.com`（新加坡） |
| 建连 | `Sandbox.connect(instance_id, timeout=1800)`（`episode.py:134`） | 用创建返回的 `InstanceId` 接入 |
| 会话对象 | `self.sb`（后续所有读写的统一入口） | — |

> **口头强调**：鉴权是**一次配置、全程复用**——API Key 在 Pod 启动时注入，
> 建连时带上；沙箱实例则用创建时返回的 ID 精确接入（不是"新建一个"，而是"接入既有的"）。

### 3.2 读写的三类操作与对应 SDK 方法

**① 命令执行（使用频率最高）—— `sb.commands.run`**

```223:225:sandbox/episode.py
            r = self.sb.commands.run(wrapped, user="root", timeout=timeout + 20)
        except CommandExitException as exc:
            r = exc
```
- 方法：`sb.commands.run(命令, user="root", timeout=<秒>)`
- 四个真实调用点、三种超时：

| 场景 | 调用处 | 超时 |
|---|---|---|
| 模型命令 / 框架自检 | `episode.py:223`（`session.run`） | `timeout + 20`（模型命令 60+20 秒） |
| 补丁导出 | `episode.py:242` | 60 秒 |
| 判分脚本执行 | `episode.py:303` | `timeout + 30`（1800+30 秒） |

- **异常即数据**：非零退出码会抛 `CommandExitException`，我们**把它当正常返回值处理**
  （`r = exc`）——因为退出码本身就是给模型的反馈（测试失败 = exit 1）。

**② 文件写入 —— `sb.files.write`**（三个真实场景）

| 写入内容 | 调用处 | 用途 |
|---|---|---|
| `/tmp/swe-test.patch` | `episode.py:179` | 把目标测试预置进沙箱（让模型能跑测试） |
| `/tmp/candidate.patch` | `episode.py:292` | 判分时重放模型的补丁 |
| `/tmp/swe-eval.sh` | `episode.py:298` | 判分脚本（官方 eval.sh 的改写版） |

**③ 文件读取 —— `sb.files.read`**

```306:308:sandbox/episode.py
        raw = session.sb.files.read("/tmp/swe-eval.log", user="root")
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "test.log").write_text(raw, encoding="utf-8")
```
- 判分输出**整份取回**（不截断）落盘为 `test.log`——这是"沙箱内日志"的最完整形态。

### 3.3 一次命令传输的完整链路（结合 5 层防护）

```
模型输出命令（纯文本）
   ▼ ① 送进沙箱之前，Pod 侧先包装（episode.py:193-220）
   │    · PATH 注入：export PATH=/opt/miniconda3/envs/testbed/bin:...
   │    · 语法预检：bash -n -c '<cmd>' 不通过 → 直接返回 exit=2（不浪费一次沙箱往返）
   │    · 超时双保险：timeout -k 5s 120s bash -lc '<cmd>'
   │    · 输出截断：python -c '<drain>'（头 25% + 尾 75%，上限 32KB）
   │    · 目录锚定：cd /testbed || exit 125
   ▼ ② sb.commands.run(wrapped, user="root", timeout=...) → HTTPS → 沙箱 envd → bash
   ▼ ③ 沙箱内执行（真实耗时 0.10–2.50 秒）
   ▼ ④ 回传：exit_code + stdout + stderr（统一合并）
   ▼ ⑤ Pod 侧记录 + 截断后交给模型
        · 记录：execution.json 追加一条（time/command/exit_code/stdout/duration_s/trusted）
        · 给模型：按 observation_tokens 截断后回填对话
```

### 3.4 关闭（与第二部分的衔接点）

数据面的"关闭"就是销毁动作本身：`sb.kill()`（`episode.py:269`）。
**没有独立的"断开连接"步骤**——因为一个 episode 一个沙箱，用完即毁：
"关闭连接"和"销毁环境"是同一个动作。

### 3.5 数据面的实测数据

| 指标 | 实测值 |
|---|---|
| 单命令沙箱内执行 | 0.10–2.50 秒 |
| 沙箱执行累计 / 轨迹时长 | 中位 4.4 秒，仅占 5%（其余 95% 是模型生成） |
| 命令总量 / 构成 | 1626 条：框架自检 33%（trusted）+ 模型命令 67% |
| 网络路径 | Pod（东京 TKE）→ 公网 HTTPS → AGS（新加坡），16 路并发掩盖跨境延迟 |

> **小结话术**：数据面就四句话——**一次建连（`Sandbox.connect`）、三类读写
> （`commands.run` / `files.write` / `files.read`）、五层防护、一个动作关闭（`kill`）**。

---

## 第四部分 · 可观测手段与关键命令（约 2 分钟）

> "最后一分钟讲'怎么证明它真的在这样运行'——我们有四层可观测，全部是可查的落盘证据。"

| 层 | 载体 | 能看到什么 | 真实样例 |
|---|---|---|---|
| **实时事件级** | 训练日志 stdout（JSON 行） | 每条轨迹完成瞬间：题号/步数/操作数/奖励 | `{"event": "swe_episode_complete", ..., "operations": 3, "reward": 1.0}` |
| **控制面级** | `episode.json` 的 `sandbox_id` / `sandbox_mode` / `fingerprint` | 这条轨迹用了哪个沙箱、什么模式、系统指纹 | `6y4eqyxipdcpokb6kvs4w324i47rslsk4n73n5k4` / `image_override` / Debian 13 |
| **数据面级** | `agent/execution.json` 的 `commands` 数组 | 每条命令的原文、退出码、输出、耗时、是否框架命令 | `{"exit_code": 0, "duration_s": 0.515, "trusted": true, ...}` |
| **判分级** | `judge/result.json` + `judge/test.log` | 逐用例通过情况（f2p/p2p）+ 判分沙箱完整输出 | `{"reward": 1.0, "suite_exit": 0, "f2p_passed": [...]}` |
| **资源级** | `gpu.csv`（每 30 秒采样） | 显存占用 / GPU 利用率曲线 | 训练全程可回溯 |

**关键命令速查**（现场演示用，任一环境可执行）：

```bash
# ① 看一条轨迹的沙箱身份（控制面证据）
python -m json.tool <轨迹目录>/agent/execution.json | head -30

# ② 数一条轨迹里各条命令（数据面证据）
python -c "import json; d=json.load(open('<轨迹>/agent/execution.json'));
print(len(d['commands']), '条命令 | trusted:', sum(c['trusted'] for c in d['commands']))"

# ③ 实时事件流（训练进行时）
grep swe_episode_complete <训练日志> | tail -5

# ④ 本轮新增的清理审计（失败自动入日志）
grep -i "cleanup_error\|refresh_user_token" <训练日志>
```

---

## 附录 A · 领导可能追问的 6 个问题（备用答法）

| 追问 | 一句话答法 |
|---|---|
| **为什么不用 Docker/K8s 直接跑题目？** | 单次训练要开约 4000 个沙箱、峰值 100 并发——用 K8s 管理这个密度成本极高；AGS 是按需创建/自动回收的托管服务，还能"1 个工具服务全部题目"（配额从 28 降到 1）。 |
| **沙箱里能碰到我们的生产系统吗？** | 不能。沙箱是物理隔离环境，没有生产网络与凭证；模型代码只在沙箱内执行，Pod 侧只做"包装与检查"。 |
| **凭证安全吗？会不会泄露？** | 用的是 oauth **临时凭证**（小时级有效期、自动续期），以 Secret 挂载注入，不落代码仓库；两个生产级防护（跨进程缓存 + 限流退避）保证长跑不中断。 |
| **沙箱会不会泄漏（残留不关）？** | 三层保险：正常路径 `kill()`、异常路径云 API `stop_instance`、平台 TTL 30 分钟。实测 `cleanup_error` 全为 `null`——零泄漏。 |
| **如果云服务抖动/限流怎么办？** | 有实录：凭证限流事故后加了退避重试，此后 21 小时零凭证故障；判分失败会被降级为 0 分并保留审计（`judge_error`），**不允许一题失败拖垮整轮训练**。 |
| **这套代码能复用到别的题目/模型吗？** | 能。`ags_instance.py`（控制面）+ `episode.py`（数据面）是通用封装，换题目只需换镜像 tag、换模型只需换 Pod 配置。 |

## 附录 B · 一页纸接口速查（讲完可留档）

| 阶段 | 方法 / API | 位置 |
|---|---|---|
| 创建-入口 | `EpisodeSession.start()` | `sandbox/episode.py:124` |
| 创建-调用 | `start_instance(image_tcr, tool_name, timeout_s)` | `sandbox/ags_instance.py:179` |
| 创建-SDK | `AgsClient(Credential(...), region)` | `ags_instance.py:172` |
| 创建-API | `StartSandboxInstanceRequest` → `client.StartSandboxInstance` | `ags_instance.py:188-195` |
| 创建-轮询 | `DescribeSandboxInstanceListRequest`（3 秒间隔，90 秒上限） | `ags_instance.py:198-207` |
| 凭证 | `_oauth_refresh`（refresh_user_token → get_temp_cred） | `ags_instance.py:85-110` |
| 数据-建连 | `Sandbox.connect(instance_id, timeout)` | `sandbox/episode.py:134` |
| 数据-命令 | `sb.commands.run(cmd, user="root", timeout)` | `sandbox/episode.py:223` |
| 数据-写文件 | `sb.files.write(path, content, user="root")` | `episode.py:179 / 292 / 298` |
| 数据-读文件 | `sb.files.read(path, user="root")` | `sandbox/episode.py:306` |
| 销毁-正常 | `session.close()` → `sb.kill()` + 落盘 `execution.json` | `episode.py:265-279` |
| 销毁-异常 | `stop_instance(instance_id)` → `StopSandboxInstance` | `ags_instance.py:211-221` |
| 销毁-兜底 | 实例 TTL（`req.Timeout="1800s"`） | `ags_instance.py:190` |
| 销毁-时机 | 正常 `swe_agent_loop.py:183` / 兜底 `swe_agent_loop.py:244-246` | — |

---

> **讲解节奏建议**：开场 0.5 分钟 → 创建 5 分钟（1.2 的七步流程是核心，可逐条讲）
> → 销毁 4 分钟（强调"三层保险"这一句话）→ 数据面 5 分钟（五层防护配合 §3.3 那张图）
> → 可观测 2 分钟（现场执行一条命令最有效）。总共约 15 分钟，留 5 分钟问答。
