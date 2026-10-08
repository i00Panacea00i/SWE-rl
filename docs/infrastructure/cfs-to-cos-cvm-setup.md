# CFS → COS 归档迁移：CVM 环境配置手册

> **配套文档**：迁移执行步骤见 [cfs-to-cos-migration-runbook.md](cfs-to-cos-migration-runbook.md)（AI 操作手册）。
> **适用场景**：TKE 集群已回收、CFS 数据（368.25 GB）需要整体归档到 COS。本手册完成"CVM 申请 → CFS 挂载 → 工具就绪"三步，之后即可进入 runbook 执行迁移。
> **全部现场参数已核实**（2026-10-08，见 §0 事实表），照此配置可直接开工。

---

## 0. 现场事实表（配置的依据，勿改）

| 项 | 值 | 来源 |
|---|---|---|
| CFS 实例 | `cfs-3qt8i05t`（名称 `swe-rl`） | `tccli cfs DescribeCfsFileSystems` |
| 数据规模 | **368.25 GB**（343 GiB） | 同上 `SizeByte` |
| 地域/可用区 | 东京 `ap-tokyo` / `ap-tokyo-1` | 同上 |
| 协议 / 带宽上限 | NFS v3 / **130 MB/s** | 同上 |
| **挂载点 IP** | **`10.0.16.9`** | `DescribeMountTargets` |
| **VPC / 子网** | **`vpc-njm2vgou`（sicheng_subnet_z2）/ `subnet-bwesplj5`（sicheng_z1）** | 同上 |
| 权限组 | `pgroupbasic`：`AuthClientIp=*`，`rw`，`no_root_squash` | `DescribeCfsRules`——**无需调整，同 VPC 内任意主机可挂载** |
| 目标 COS bucket（待建） | `swe-rl-archive-1437615650` @ `ap-tokyo` | 建议值（1437615650 为 AppID 后缀，全局唯一） |
| 归档前缀 | `swe-rl-20261008/` | 建议值（带日期，支持多次归档共存） |

---

## 1. CVM 申请（控制台操作，约 5 分钟）

### 1.1 关键参数（每一项都有硬理由）

| 配置项 | 选择 | 理由 |
|---|---|---|
| 地域 | **东京（ap-tokyo）** | 与 CFS 同地域；COS 上传走同区内网（免流量费、速度快） |
| 网络 | **VPC `vpc-njm2vgou` / 子网 `subnet-bwesplj5`** | ★ **必须与 CFS 挂载点同 VPC**——选错则内网不通，挂载直接失败 |
| 机型 | 标准型 SA5 或 S5，**2 核 4 GB** | 上传是网络/IO 型任务，CPU 几乎空闲；coscli 为 Go 单二进制，内存占用低 |
| 镜像 | Ubuntu 22.04 LTS（或 TencentOS Server 3.1） | 两条 NFS 挂载命令都已在 §2 给出 |
| 系统盘 | 50 GB 高性能云硬盘 | 存放工具、迁移日志、对账清单与抽样校验文件 |
| 带宽 | **按量计费，10 Mbps 即可** | COS 走内网不占公网带宽；公网仅用于 SSH 管理 |
| 安全组 | 入站放通 22（建议限制来源 IP）；出站默认全放通 | 出站需可达内网 443（COS） |
| 计费模式 | **按量计费**（用完立即销毁） | 本次迁移预计 2-5 小时，成本约 1-3 元 |

### 1.2 控制台路径

```
云服务器 CVM → 新建实例 → 按上述参数填写 → 设置公网 IP（按量）→ 安全组 → 确认
```

> 注：若提示"该 VPC 下无可用子网"，确认地域已切换到东京再选 VPC（`vpc-njm2vgou` 在东京地域）。

---

## 2. 挂载 CFS（CVM 上执行，约 2 分钟）

```bash
# ① 安装 NFS 客户端
# Ubuntu / Debian:
sudo apt update && sudo apt install -y nfs-common
# TencentOS / CentOS 替代命令:
# sudo yum install -y nfs-utils

# ② 挂载（参数为腾讯云 CFS 官方推荐组合，勿简化）
sudo mkdir -p /mnt/cfs
sudo mount -t nfs \
  -o vers=3,nolock,proto=tcp,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
  10.0.16.9:/ /mnt/cfs

# ③ 验证三步
ls /mnt/cfs                      # 应看到 swe-rl 目录
du -sh /mnt/cfs/swe-rl           # 应约 343G（368.25 GB）
df -h | grep cfs                 # 应显示 10.0.16.9:/  挂载正常
```

**开机自动挂载（可选，长任务建议加）**：

```bash
echo '10.0.16.9:/ /mnt/cfs nfs vers=3,nolock,proto=tcp,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0' | sudo tee -a /etc/fstab
```

**挂载失败排查**（按顺序）：

| 现象 | 检查 |
|---|---|
| `mount: connection timed out` | CVM 是否在 `vpc-njm2vgou` / `subnet-bwesplj5`；`ping 10.0.16.9` 是否通 |
| `permission denied` | 权限组已确认全放通（`*` / `rw`），如异常：`tccli cfs DescribeCfsRules --PGroupId pgroupbasic --region ap-tokyo` |
| `wrong fs type` | NFS 客户端未装（回 §2 ①） |

---

## 3. 工具安装与凭证配置（约 5 分钟）

### 3.1 主工具：coscli（推荐——多文件并发、断点续传、失败清单齐全）

```bash
# ① 下载（官方 v1.0.9，GitHub Releases）
wget https://github.com/tencentyun/coscli/releases/download/v1.0.9/coscli-v1.0.9-linux-amd64 -O coscli
chmod +x coscli && sudo mv coscli /usr/local/bin/
coscli --version          # 应输出版本号

# ② 配置（长期密钥 + 目标 bucket）
coscli config add -b swe-rl-archive-1437615650 -r ap-tokyo -i <SecretId> -k <SecretKey>
coscli config ls          # 验证（密钥脱敏显示）
```

> **凭证选择（重要）**：批量迁移**务必使用长期密钥**（控制台「访问管理 → API 密钥管理」创建）。临时密钥（含 Token，如 oauth 凭证）有时效，长时间迁移中途失效会导致任务中断。
> **最小权限建议**：单独创建一个子用户，仅授予 `swe-rl-archive-1437615650` 桶的 `PutObject` / `GetObject` / `ListBucket` 权限。

### 3.2 兜底工具：tccli（参数齐全，已验证可用）

```bash
sudo apt install -y python3-pip
pip3 install tccli cos-python-sdk-v5
tccli configure           # 按提示输入 SecretId / SecretKey（Token 留空或填临时密钥 Token）
tccli cos list_buckets --region ap-tokyo    # 验证：应列出 bucket（含待建的目标桶）
```

### 3.3 目标 bucket 准备（若尚未创建）

```bash
tccli cos create_bucket --bucket swe-rl-archive-1437615650 --region ap-tokyo
tccli cos list --bucket swe-rl-archive-1437615650 --region ap-tokyo   # 应为空列表
```

> 若改用其它桶名：全局唯一即可，但需同步修改 runbook 中全部目标路径。

---

## 4. 就绪自检清单（全部通过后进入 runbook）

| # | 检查项 | 命令 | 期望 |
|---|---|---|---|
| 1 | CFS 已挂载 | `df -h \| grep cfs` | 显示 `10.0.16.9:/` |
| 2 | 数据可见 | `ls /mnt/cfs/swe-rl/` | 见 `model/ checkpoints/ traces/ logs/ data/ archive/` |
| 3 | 容量一致 | `du -sh /mnt/cfs/swe-rl` | ≈ 343G |
| 4 | coscli 就绪 | `coscli config ls` | 显示目标 bucket 配置 |
| 5 | COS 内网连通 | `curl -sI https://cos.ap-tokyo.myqcloud.com \| head -1` | 返回 HTTP 状态（403 亦属连通） |
| 6 | bucket 可写 | `echo hello \| coscli cp - cos://swe-rl-archive-1437615650/_smoke.txt && coscli rm cos://swe-rl-archive-1437615650/_smoke.txt` | 无报错 |
| 7 | 磁盘余量 | `df -h /` | 系统盘剩余 >20 GB（放清单与校验文件） |

---

## 5. 安全与成本

**安全**：
- 密钥只写入 `~/.cos.yaml`（`chmod 600`）与 `~/.tccli/`，**不要**出现在命令行历史或文档中；
- 安全组入站 22 建议限定来源 IP；迁移结束立即销毁 CVM；
- 目标 bucket 保持**私有读写**（默认），不做公开授权。

**成本预估**：

| 项 | 预估 | 说明 |
|---|---|---|
| CVM（2C4G 按量） | ~0.3 元/小时 × 3-5 小时 ≈ **1-2 元** | 用完销毁 |
| COS 存储（东京） | 368 GB ≈ **8.5 美元/月**（标准）或 **~1.2 美元/月**（归档，见 runbook §7） | 长期成本主体 |
| 对比：CFS 现状 | 368 GB 标准型 ≈ 150-200 元/月 | **迁移后删除 CFS 即释放** |

---

## 6. 与 runbook 的衔接

环境就绪后，直接按 [cfs-to-cos-migration-runbook.md](cfs-to-cos-migration-runbook.md) 执行：

```
§1 环境自检 → §2 生成清单 → §3 bucket 校验 → §4 试传标定 → §5 全量上传 → §6 对账 → §7 收尾
                    （人工确认点 ①建桶    （实测速率外推耗时）  （人工确认点 ②开始）  （人工确认点 ③删 CFS）
```

> **原则**：本手册只做"让机器准备好"，所有写操作（建桶、上传、删除）都在 runbook 中执行且带确认点。
