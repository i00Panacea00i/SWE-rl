#!/usr/bin/env bash
# 数据画像链：4 批顺序执行（配额准入门控 + 沙箱回收窗口 + 末尾自动汇总）。
# 幂等：已 Succeeded 的批次自动跳过；中断后原样重跑即可续跑。
# 前置：GPU 节点就绪（Pod 通过 nvidia.com/gpu=4 资源请求调度）。
set -uo pipefail
cd "$(dirname "$0")/.."
LOG=/tmp/profile-chain.log
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "=== 画像链启动（67 题 × n=4 = 268 轨迹，4 批）==="
for i in 1 2 3 4; do
  POD="swe-rl-profile-$i"
  PHASE=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$PHASE" = "Succeeded" ]; then log "$POD 已完成，跳过"; continue; fi

  ok=0
  for a in $(seq 1 36); do
    if venv/bin/python scripts/quota_probe.py >/dev/null 2>&1; then ok=1; log "$POD 配额 OK（第 $a 次探测）"; break; fi
    log "$POD 配额忙（$a/36），300s 后重试"; sleep 300
  done
  [ "$ok" = 1 ] || { log "$POD 配额超时，中止（可重跑续传）"; exit 1; }

  kubectl delete pod "$POD" --wait=false >/dev/null 2>&1; sleep 3
  kubectl apply -f "deploy/profile/profile-$i.yaml" >/dev/null || { log "$POD 启动失败"; exit 1; }
  log "$POD 已启动，等待完成"

  PHASE=""
  for w in $(seq 1 100); do
    sleep 60
    PHASE=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$PHASE" = "Succeeded" ] || [ "$PHASE" = "Failed" ]; then break; fi
  done
  log "$POD 终态: $PHASE ($(kubectl logs "$POD" 2>/dev/null | grep -oE '完成 \| pass@[0-9] = [0-9.]+ \([0-9]+/[0-9]+\)' | tail -1))"
  sleep 90   # 沙箱 TTL 回收窗口
done

log "=== 4 批完成。汇总输出见 /mnt/cfs/swe-rl/logs/profile-summary.json（由 profile-4 末尾生成）==="
log "=== 链完成 ==="
