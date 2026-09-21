# 02 · 基础设施与集群问题（Infrastructure）

> 网络出口、DNS、集群迁移、公网 API、镜像拉取——项目期间所有基础设施层故障的根因与修复。

---

## 1. NAT 网关缺失——节点无法出公网

**现象**：节点内 `pip install` / 拉取 GitHub / 连接 AGS 全部超时；`ContainerCreating` 卡死（拉镜像失败）。

**根因**：GPU 节点所在子网的路由表**没有 `0.0.0.0/0` 默认路由**（或未指向 NAT 网关）——只能内网互通，公网出不去。

**修复**：
```bash
# 1) 确认路由表（应看到 0.0.0.0/0 → NAT）
tccli vpc DescribeRouteTables --region ap-tokyo
# 2) 创建/挂载 NAT 网关后在子网路由表添加默认路由
#    0.0.0.0/0 → GatewayType=NAT, GatewayId=nat-xxxxx
```
节点与 Pod 双路径验证（节点 hostNetwork + Pod 网络分别测 pypi/AGS/TCR）。

**沉淀**：新集群/新子网必须检查三件套：**默认路由（NAT）+ DNS + 安全组出站**——任何"能 ping 通内网但出不了公网"都先查路由表。

---

## 2. AGS 域名"黑洞"误判——一次方法论教训 ⚠️

**现象**：`ap-singapore.tencentags.com` 解析返回 `0.0.0.1`（全球所有 DNS + DoH 权威查询一致）；据此误判"AGS 平台全球故障/迁移"。

**根因（真实情况）**：**SDK 从不连接裸域**——e2b SDK 内部会构造 `api.ap-singapore.tencentags.com`（真 IP）与 `e2b.ap-singapore.tencentags.com`。裸域 A 记录被平台置为黑洞**对 SDK 零影响**。误判源于"用裸域而非 SDK 真实路径做连通性验证"。

**修复**：无需修复（平台正常）。验证动作：直接跑 `Sandbox.create()` 端到端测试（CVM 与 Pod 双路径），全通。

**沉淀（三条）**：
1. **连通性验证必须复刻 SDK 的真实请求路径**（域名构造逻辑），而不是"拼一个看起来对的域名"；
2. 排查 DNS 异常先用 **DoH 权威查询**（dns.google / cloudflare-dns.com）排除本地劫持，再判断平台侧；
3. 平台侧行为变化（如裸域下沉）不等于服务故障——**以 SDK 实测为最终裁决**。

---

## 3. 集群访问中断与迁移（老集群 → 新集群）

**现象**：某日 `kubectl get nodes` 超时；`dial tcp 203.0.113.10:443: i/o timeout`（ICMP 通但 TCP 443 不通）；老集群 `DescribeClusterInstances` 返回空——老集群无节点、API 不可达。

**根因**：平台侧进行集群切换——老集群被下线（CLB 拒绝服务），新集群 `sichenggpuZ1`（cls-<id>）已就绪但**只配了内网域名**（`cls-<id>.ccs.tencent-cloud.com`，仅 VPC 内可解析）。

**修复（逐步）**：
```bash
# 1) 取新集群 kubeconfig
tccli tke DescribeClusterKubeconfig --ClusterId cls-<id> --region ap-tokyo > new-cluster.yaml
# 2) 发现外网端点为空 → 开通公网 API（复用既有 ACL 安全组）
tccli tke CreateClusterEndpoint --ClusterId cls-<id> --IsExtranet true \
    --SecurityGroup sg-<id>        # 入站仅 443 + 本机 IP/32
# 3) kubeconfig server 替换为公网 CLB 域名 → kubectl get nodes 成功
# 4) 切换默认 kubeconfig（备份旧配置）
cp ~/.kube/config ~/.kube/config.old && cp new-cluster.yaml ~/.kube/config
```

**沉淀**：
- 集群迁移检查清单：kubeconfig → 公网端点（或 VPN/跳板）→ ACL 安全组 → PVC/secret 重建 → 节点 GPU 标签。
- ACL 安全组做法：**只放行管理机 IP 的 443**（最小暴露面）。
- ICMP 通但 TCP 443 不通 ≈ 服务端拒绝/下线，不是网络断——分端口测试（`/dev/tcp/<ip>/443`）。

---

## 4. PVC 与存储（新集群无 CFS CSI）

**现象**：新集群 StorageClass 只有 `cbs`（云硬盘），没有 CFS 类型；挂载共享存储无路。

**修复**：**K8s 原生 NFS PV 直挂**（无需安装任何 CSI 组件）：
```yaml
# deploy/pvc.yaml
apiVersion: v1
kind: PersistentVolume
spec:
  nfs: { server: 10.0.0.x, path: / }     # CFS 挂载点
  accessModes: [ReadWriteMany]
  storageClassName: swe-rl-cfs
```

**沉淀**：CFS 本质是 NFS——跨集群迁移时"原生 NFS PV"是最简路径；先用 `du -sh` 对比目录大小差异注意 **overlayfs vs CFS 的 inode 统计差异**（曾因此误判"文件损坏"，实际逐文件校验全通过）。

---

## 5. 镜像拉取问题

### 5.1 DockerHub 可达性（NAT 修好后）
节点经 NAT 可拉 `docker.io`——12.3GB verl 镜像约 10 分钟。**提前用一枚"预载 Pod"把训练镜像拉到节点缓存**，避免正式训练再等。

### 5.2 镜像 digest 笔误（ImagePullBackOff）
**现象**：`Failed to pull image`——manifest unknown。
**根因**：手工抄写 digest 少了一截（`...922d0eb9a58e920668f01be0b549880f7f9e` vs 正确 `...922a28c5bd0409e2a324e3ee70fb27ca7543`）。
**修复**：从历史清单 `grep -oE "verlai/verl[:@][^ ]+"` 取回原始引用，或 `docker inspect --format='{{index .RepoDigests 0}}'` 反查。
**沉淀**：digest 永远复制粘贴，不手打；拉取失败先用 `docker manifest inspect <ref>` 验证存在性。

### 5.3"空环境"镜像陷阱（uv.cu130）
**现象**：某官方新镜像 29.9GB，拉取推送半天后才发现 `/usr/bin/python3.12` 里**没有 vllm/torch**——依赖需运行时用 uv 在线安装。
**修复**：弃用，改用已验证的全功能镜像（vllm024 系列）。
**沉淀**：切镜像前先 `docker run --entrypoint <python> -c "import vllm"` 做**功能冒烟**（30 秒成本 vs 半天浪费）。

---

## 6. CFS 访问路径（开发机不在集群 VPC 时）

**现象**：`kubectl cp` 慢且不稳；尝试从开发机直连 CFS（`10.0.0.x:2049`）——不可达（跨 VPC 无对等）。

**修复**：**sync Pod 中转**——集群内起一个挂载 CFS 的小 Pod（`deploy/sync-kit.yaml`），所有读写走 `kubectl exec/cp`。
**注意**：sync Pod 是短命 Pod（命令跑完即退出）——访问前若 `Completed` 需先重启：
```bash
kubectl delete pod swe-rl-sync --wait=true && kubectl apply -f deploy/sync-kit.yaml
kubectl wait --for=condition=Ready pod/swe-rl-sync --timeout=80s
```

**沉淀**：跨 VPC 场景"一跳中转 Pod"是标准解法；把所有 CFS 操作封装成 `kubectl exec swe-rl-sync -- …` 即可复用。
