# CFS → COS 归档迁移：AI 操作手册（Runbook）

> **读者**：执行迁移的 AI agent（本手册为逐步可执行的命令级指令）与其中 3 个确认点的决策人。
> **前置**：[cfs-to-cos-cvm-setup.md](cfs-to-cos-cvm-setup.md) 已全部完成（CVM 上 CFS 可用、coscli 就绪）。
> **执行位置**：全部命令在**东京 CVM** 上执行（SSH 进入后）。本地电脑不参与搬运。

---

## 0. 执行契约（先读，全程遵守）

### 0.1 现场常量（下文命令中的占位符一律替换为这些值）

| 占位符 | 值 |
|---|---|
| `$CFS` | `/mnt/cfs/swe-rl`（挂载后的源路径） |
| `$BUCKET` | `swe-rl-archive-1437615650` |
| `$REGION` | `ap-tokyo` |
| `$PREFIX` | `swe-rl-20261008`（归档前缀，带日期） |
| `$COS` | `cos://swe-rl-archive-1437615650/swe-rl-20261008`（目标地址，下同） |

### 0.2 三个不可跳过的**人工确认点**

| # | 时机 | 确认内容 |
|---|---|---|
| ① | 阶段三（建桶前） | bucket 名与归档前缀最终确认（一旦开始上传即固化） |
| ② | 阶段四结束（全量前） | 查看试传实测速率与耗时外推，确认开始全量 |
| ③ | 阶段七（删除 CFS 前） | 对账报告复核后，**单独指令**才可删除 CFS（本手册默认不执行删除） |

### 0.3 执行纪律

1. **幂等**：所有上传命令可**原样重跑**（`coscli sync` 语义 = 只传差异），中断后重跑即续；
2. **留痕**：每条命令输出 `tee` 到 `/root/migration-logs/`，每个阶段结束写一行 `STATUS` 记录（格式见 §8）；
3. **逐文件失败隔离**：任何批量命令必须带 `--fail-output`，失败清单单独重试，绝不让"一个文件挂掉整个命令"；
4. **不猜**：每次"期望输出"不匹配时，先停下执行对应排查项，不带着异常进入下一阶段。

---

## 1. 阶段一：环境自检（S1）

```bash
mkdir -p /root/migration-logs && cd /root/migration-logs

# 1.1 CFS 挂载与数据
df -h | grep cfs
ls /mnt/cfs/swe-rl/
du -sh /mnt/cfs/swe-rl/

# 1.2 工具就绪
coscli --version
coscli config ls

# 1.3 COS 连通与 bucket
tccli cos list_buckets --region ap-tokyo | grep swe-rl-archive-1437615650 || echo "BUCKET_NOT_EXIST"
```

**验收标准**：`df` 见 `10.0.16.9:/`；`du` ≈ 343G；coscli 版本号正常；bucket 存在（否则进入阶段三）。

---

## 2. 阶段二：生成迁移清单（S2）

> 清单是**最终对账的唯一基线**，必须先于任何上传生成。

```bash
# 2.1 目录级规模（先看结构，10 秒级）
du -sh /mnt/cfs/swe-rl/* | sort -h | tee dir-sizes.txt

# 2.2 全量文件清单（海量小文件，可能耗时 5-15 分钟）
find /mnt/cfs/swe-rl -type f -printf '%P\t%s\n' | sort > /root/migration-manifest.tsv
wc -l /root/migration-manifest.tsv
awk -F'\t' '{s+=$2} END {print "total_bytes:", s, "total_GB:", s/1024/1024/1024}' /root/migration-manifest.tsv
```

**验收标准**：
- 总字节与阶段一 `du` 数量级一致（差异 <1%，du 的块对齐会有少量偏差）；
- 记录三个数字到 `STATUS`：**文件数 / 总字节 / 目录数**——它们将用于阶段六对账。

**注意**：若 `find` 报 `Stale file handle`，重跑一次；持续报错则该目录单独处理并在报告中标记。

---

## 3. 阶段三：bucket 准备（S3）【人工确认点 ①】

```bash
# 3.1 若不存在则创建（确认点 ① 通过后执行）
tccli cos create_bucket --bucket swe-rl-archive-1437615650 --region ap-tokyo

# 3.2 确认空桶 + 记录
tccli cos list --bucket swe-rl-archive-1437615650 --region ap-tokyo
```

**验收标准**：bucket 存在且为空（若已有旧归档内容，记下对象清单——避免与本次前缀冲突）。

---

## 4. 阶段四：试传与速率标定（S4）

> 目的：用最小代价验证"链路 + 参数 + 速率"，并外推全量耗时。

```bash
# 4.1 选一个小目录试传（archive/ 约 679MB，最能代表"混合文件"场景）
time coscli sync /mnt/cfs/swe-rl/archive $COS/archive \
  --thread-num 16 --routines 4 --part-size 8 \
  --fail-output --fail-output-path /root/migration-logs/fail-archive.txt \
  2>&1 | tee /root/migration-logs/s4-archive.log
```

```bash
# 4.2 局部对账（对象数与字节）
tccli cos list --bucket swe-rl-archive-1437615650 --region ap-tokyo \
  --prefix swe-rl-20261008/archive/ --recursive | wc -l
du -sb /mnt/cfs/swe-rl/archive
cat /root/migration-logs/fail-archive.txt 2>/dev/null   # 应为空
```

**决策表（据实测速率）**：

| 实测速率 | 判定 | 动作 |
|---|---|---|
| ≥ 60 MB/s | 链路健康 | 直接用当前参数进入阶段五（外推：368GB ≈ 1.7 小时） |
| 30-60 MB/s | 可接受 | 进入阶段五；可将 `--thread-num` 提升到 24 再试 1 分钟观察 |
| < 30 MB/s | 异常 | 排查：① 是否误走公网（`--endpoint` 检查）；② CFS 读带宽是否被其它任务占用；③ 提升 `--thread-num 32 --routines 8` 重测 |

**耗时外推**（记录到 STATUS）：`预计全量耗时 ≈ 368.25GB ÷ 实测速率 × 1.3`（小文件开销系数）。

---

## 5. 阶段五：全量上传（S5）【人工确认点 ② 后执行】

### 5.1 上传顺序（大文件在前——早发现链路问题，小文件目录最后）

| 序 | 目录 | 规模 | 说明 |
|---|---|---|---|
| 1 | `model/` | ~122 GB | 基座与合并模型（大文件为主，速率最高） |
| 2 | `checkpoints/` | ~1 GB | 训练检查点（含 LoRA adapter） |
| 3 | `logs/` | ~7 GB | 训练日志 + GPU 采样 |
| 4 | `archive/` | 0.7 GB | 已试传，`sync` 自动跳过 |
| 5 | `traces/` | ~数 GB / **海量小文件** | 耗时最长，放最后 |
| 6 | `data/` + 根目录散件 | 小 | 收尾 |
| 7 | `tools/`、其它 | 小 | `ls $CFS` 核对补漏 |

### 5.2 单目录命令模板（对每个目录循环执行）

```bash
cd /root/migration-logs
D=<目录名>    # 例如 model
time coscli sync /mnt/cfs/swe-rl/$D $COS/$D \
  --thread-num 16 --routines 4 --part-size 8 \
  --fail-output --fail-output-path /root/migration-logs/fail-$D.txt \
  2>&1 | tee /root/migration-logs/s5-$D.log
```

**执行要点**：
- `coscli sync` = **只上传有差异的文件**（mtime/size 判定）→ 天然支持中断续传与重跑；
- 每个目录完成后立即检查 `fail-$D.txt`（应为空）；非空则只对该清单重跑同一命令；
- 每个目录完成后执行一次**局部对账**（同 §4.2 方式，替换 prefix）。

### 5.3 断点与异常处理

| 情况 | 动作 |
|---|---|
| SSH 断连 / 命令中断 | 重新 SSH，**原样重跑该目录的 sync 命令**（已完成文件跳过） |
| `fail-*.txt` 非空 | 对该清单逐文件重试（见附录 A-2） |
| 临时密钥过期（如误用） | `coscli config add` 更新凭证后重跑 |
| 速率骤降 | 检查 CFS 侧其它进程；必要时降到 `--thread-num 8` 减少竞争 |

### 5.4 全量完成检查

```bash
# 所有目录 fail 清单应为空
ls -la /root/migration-logs/fail-*.txt
for f in /root/migration-logs/fail-*.txt; do echo "== $f"; wc -c "$f"; done
```

---

## 6. 阶段六：对账校验（S6）

### 6.1 全量对象清单（COS 侧）

```bash
# 拉取 COS 侧完整清单（仅列对象路径与大小）
tccli cos list --bucket swe-rl-archive-1437615650 --region ap-tokyo \
  --prefix swe-rl-20261008/ --recursive > /root/migration-logs/cos-list.txt
wc -l /root/migration-logs/cos-list.txt
```

### 6.2 三项对账

```bash
# ① 对象数 vs 清单行数
echo "local:  $(wc -l < /root/migration-manifest.tsv)"
echo "cos:    $(grep -c 'swe-rl-20261008/' /root/migration-logs/cos-list.txt)"

# ② 总字节对比（COS 侧从 list 输出解析大小列，格式以实际输出为准）
#    也可用 coscli 统计：
coscli ls -r $COS | tail -3

# ③ 缺失文件差集（本地清单 vs COS 清单）
#    生成缺失列表（如为空则完全一致）
comm -23 \
  <(cut -f1 /root/migration-manifest.tsv | sort) \
  <(grep 'swe-rl-20261008/' /root/migration-logs/cos-list.txt | awk '{print $NF}' | sed 's|swe-rl-20261008/||' | sort) \
  > /root/migration-logs/missing.txt
wc -l /root/migration-logs/missing.txt
```

### 6.3 抽样内容校验（防"数量对但内容错"）

```bash
# 随机抽 1 个小文件 + 1 个大文件（>50MB），下载回本地目录对比 md5
mkdir -p /root/verify && cd /root/verify
# 小文件（示例：取一个 traces 里的 json）
SMALL=$(find /mnt/cfs/swe-rl/traces -type f -name '*.json' | head -1)
md5sum "$SMALL"
coscli cp cos://swe-rl-archive-1437615650/swe-rl-20261008/${SMALL#/mnt/cfs/swe-rl/} ./verify-small -f && md5sum ./verify-small

# 大文件（取 model 下一个分片）
BIG=$(find /mnt/cfs/swe-rl/model -type f -size +50M | head -1)
md5sum "$BIG"
coscli cp cos://swe-rl-archive-1437615650/swe-rl-20261008/${BIG#/mnt/cfs/swe-rl/} ./verify-big -f && md5sum ./verify-big
# ⚠️ 必须下载回验——大文件分片上传的 ETag ≠ md5，不可直接用 COS 对象 ETag 对比
```

### 6.4 验收标准与收尾动作

| 检查 | 通过标准 | 不通过动作 |
|---|---|---|
| 对象数 | 与清单行数一致（误差 0） | 用 `missing.txt` 重传缺失项 |
| 总字节 | 与清单合计一致（误差 <0.1%） | 定位差异目录，重跑对应 sync |
| 抽样 md5 | 小/大文件各 ≥1 个完全一致 | 扩大抽样（≥5 个），若仍不符排查内容编码问题 |
| fail 清单 | 全部为空 | 逐文件重试 |

```bash
# 生成校验报告（双份存放：CVM 本地 + 上传回 COS）
cat > /root/migration-logs/VERIFY-REPORT.md <<EOF
# CFS→COS 迁移校验报告
- 日期: $(date -u +%FT%TZ)
- 源: cfs-3qt8i05t /mnt/cfs/swe-rl
- 目标: cos://swe-rl-archive-1437615650/swe-rl-20261008/
- 文件数: 本地 $(wc -l < /root/migration-manifest.tsv) / COS $(grep -c 'swe-rl-20261008/' /root/migration-logs/cos-list.txt)
- 缺失清单: $(wc -l < /root/migration-logs/missing.txt) 项
- 抽样 md5: 见上文输出（小文件/大文件各 1）
EOF
coscli cp /root/migration-logs/VERIFY-REPORT.md cos://swe-rl-archive-1437615650/swe-rl-20261008/VERIFY-REPORT.md -f
```

---

## 7. 阶段七：收尾（S7）【人工确认点 ③】

### 7.1 存储成本优化（可选，决策点）

| 选项 | 操作 | 适用 |
|---|---|---|
| **A. 全部保持 STANDARD** | 不操作 | 未来 2-4 周内可能需要回拉数据（最稳） |
| **B. 冷目录转归档存储** | 对 `traces/`、`logs/`、`archive/`、旧模型分片配置**生命周期规则**：控制台 → COS → 桶 → 生命周期 → 30 天后转 ARCHIVE | 只归档、极少回读（月成本 ≈ 1/7） |
| **C. 立即指定归档类型重传** | `coscli sync ... --storage-class ARCHIVE` | 不推荐：归档存储有最短存储期与取回费用，先按 A/B 更稳 |

> 推荐：**先 A；稳定 2-4 周后按 B 配置生命周期**（转换在线完成，无需重传）。本步非必须，不影响迁移完成判定。

### 7.2 归档完成清单

```bash
# ① 迁移日志打包上传（执行证据随归档一起保存）
tar czf /root/migration-logs.tar.gz /root/migration-logs
coscli cp /root/migration-logs.tar.gz cos://swe-rl-archive-1437615650/swe-rl-20261008/_migration-logs.tar.gz -f

# ② 汇总 STATUS（见 §8）
cat /root/migration-logs/STATUS.txt
```

### 7.3 冻结期与删除（人工执行，AI 不代劳）

- **CFS 至少保留 2 周**再做删除决策（对账通过 ≠ 业务侧确认无损）；
- 删除 CFS（危险操作，需单独指令）：
  ```bash
  # 仅供人工决策后执行：
  # tccli cfs DeleteCfsFileSystem --FileSystemId cfs-3qt8i05t --region ap-tokyo
  ```
- CVM 销毁：确认 `migration-logs.tar.gz` 已上传后端销毁（按量计费停止）。

---

## 8. STATUS 记录格式（贯穿全程）

每个阶段结束向 `/root/migration-logs/STATUS.txt` 追加一行：

```
S1 OK 2026-10-08T03:10Z cfs=ok cos=ok
S2 OK 2026-10-08T03:40Z files=312456 total_GB=343 dirs=23
S4 OK 2026-10-08T04:05Z rate=78MB/s eta=2.1h
S5-model OK ... S5-traces OK ...（按目录逐行）
S6 OK files_match=1 bytes_match=1 md5_samples=2/2
S7 OK logs_uploaded=1
```

---

## 附录 A：失败模式速查表

| # | 现象 | 根因 | 处理 |
|---|---|---|---|
| A-1 | `some upload_part fail after max_retry` | 分片上传失败（历史跨区同源问题） | 降参数重试：`--thread-num 8 --routines 2 --part-size 4`；tccli 兜底加 `--retry 10` |
| A-2 | `fail-*.txt` 有失败文件 | 单文件级失败 | 逐文件重试（coscli 支持单文件 cp），直到清单为空 |
| A-3 | 速率骤降至 <10MB/s | 并发过高触发限流 / CFS 读竞争 | 降 `--thread-num` 至 8-12；错峰 |
| A-4 | `Stale file handle`（NFS） | CFS 连接抖动 | 重新挂载后重跑（sync 幂等，无损失） |
| A-5 | `Access Denied` | 凭证/权限 | 检查密钥、bucket 权限策略（PutObject/ListBucket） |
| A-6 | 临时密钥过期 | 误用短期凭证 | 换长期密钥重配后重跑 |
| A-7 | COS 侧对象数少于本地 | 静默跳过（罕见） | 用 §6.2 差集定位缺失 → 重传 |

## 附录 B：参数速查（两套工具）

**coscli（主用）**：

| 参数 | 推荐值 | 作用 |
|---|---|---|
| `--thread-num` | 16（限流时降 8） | 多文件并发 |
| `--routines` | 4 | 单文件分片并发 |
| `--part-size` | 8（MB） | 分片大小 |
| `--fail-output` | 必带 | 失败清单 |
| （断点续传） | 重跑同命令 | checkpoint 默认 `~/.cos_checkpoint` |

**tccli（兜底）**：`tccli cos sync_upload --bucket <b> --local_path <dir> --cos_key <prefix>/ --recursive true --ignore_existing true --routines 8 --thread_num 3 --part_size 8 --retry 10 --log_file /root/tccli-upload.log`

## 附录 C：时间与容量基准（更新于实测后）

| 项 | 值 |
|---|---|
| 数据总量 | 368.25 GB（CFS `SizeByte`） |
| CFS 带宽上限 | 130 MB/s（理论最短 ≈ 47 分钟） |
| 预期实际耗时 | **1.5-4 小时**（小文件占比决定；以阶段四实测外推为准） |
| 对象数预估 | 10 万+-级（traces 目录为主，阶段二给出精确值） |

---

> **本手册的更新约定**：迁移执行完成后，把实测速率、实际耗时、遇到的问题回填到附录 C 与 A（形成下一次归档的基准）；校验报告归档到 COS 的 `swe-rl-20261008/VERIFY-REPORT.md`。
