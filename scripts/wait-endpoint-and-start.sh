#!/usr/bin/env bash
# 无人值守：等待集群外网端点就绪 → 更新 kubeconfig → 启动画像链。
# 用途：用户在 TKE 控制台开启「外网访问」后，本脚本自动接管后续全部步骤。
# 每 2 分钟探测一次，最多等 2 小时。
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=/tmp/wait-endpoint.log
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG"; }

CLUSTER=cls-ro74kviw
REGION=ap-tokyo

log "=== 等待集群 $CLUSTER 外网端点（每 2 分钟探测，上限 2 小时）==="
for i in $(seq 1 60); do
  ST=$(timeout 20 tccli tke DescribeClusterEndpointStatus --region "$REGION" --ClusterId "$CLUSTER" 2>/dev/null \
       | grep -o '"Status": "[^"]*"' | head -1 | cut -d'"' -f4)
  log "[$i/60] 端点状态: ${ST:-查询失败}"

  if [ "$ST" = "Created" ] || [ "$ST" = "Running" ]; then
    log "端点就绪 → 拉取最新 kubeconfig"
    timeout 25 tccli tke DescribeClusterKubeconfig --region "$REGION" --ClusterId "$CLUSTER" > /tmp/kc_new.json 2>/dev/null
    cp ~/.kube/config "$HOME/.kube/config.pre-wait-$(date +%s)" 2>/dev/null || true
    venv/bin/python - <<'PY' 2>&1 | tee -a "$LOG"
import json
d = json.load(open('/tmp/kc_new.json'))
kc = d.get('Kubeconfig', '')
open('/root/.kube/config', 'w').write(kc)
srv = [l.strip() for l in kc.splitlines() if 'server:' in l]
print('[wait] 新 server:', srv)
PY
    if timeout 25 kubectl get nodes --request-timeout=20s >/dev/null 2>&1; then
      log "✅ kubectl 连通，节点列表："
      kubectl get nodes --no-headers 2>&1 | tee -a "$LOG"
      log "启动画像链"
      pkill -f profile-chain 2>/dev/null || true
      sleep 1
      setsid nohup bash scripts/profile-chain.sh >/tmp/profile-chain.out 2>&1 </dev/null &
      log "画像链已启动（后台）→ 进度见 /tmp/profile-chain.log"
      exit 0
    else
      log "kubectl 仍不通（server 可能仍是内网端点，或白名单未含本机 IP 43.156.182.139）"
    fi
  fi
  sleep 120
done
log "=== 超时 2 小时退出（可重跑本脚本续等）==="
