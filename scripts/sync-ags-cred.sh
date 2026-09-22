#!/usr/bin/env bash
# 同步本机 tccli 凭据到集群 secret（修复 AGS/ApiServer 凭据刷新失败）。
#
# 背景（2026-09-22 实际事故）：
#   Pod 挂载的 secret `tccli-credential` 是凭据快照；本机 tccli 刷新会轮换
#   refreshToken（OAuth 轮换制），旧快照随即失效 → 沙箱创建报
#   `refresh_user_token failed: Code=FailedOperation.RefreshTok...`（现象：沙箱就绪 0/N）。
#   本脚本：先确认本机凭据有效 → 同步到 secret → 一致性校验。
#
# 用法：bash scripts/sync-ags-cred.sh  （之后重启相关 Pod 才会挂载新 secret）
set -euo pipefail
cd "$(dirname "$0")/.."

CRED="$HOME/.tccli/default.credential"
[ -f "$CRED" ] || { echo "❌ 本机凭据不存在: $CRED（需先 tccli auth login）"; exit 2; }

echo "=== 1. 本机凭据健康检查（必要时会自动刷新）==="
if timeout 40 tccli tke DescribeClusters --region ap-tokyo --Limit 1 >/dev/null 2>&1; then
  echo "✓ 本机凭据有效"
else
  echo "❌ 本机凭据无效——请先执行 tccli auth login"; exit 2
fi

echo "=== 2. 同步到集群 secret ==="
kubectl create secret generic tccli-credential \
  --from-file=default.credential="$CRED" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "✓ secret/tccli-credential 已更新"

echo "=== 3. 一致性校验 ==="
S=$(kubectl get secret tccli-credential -o jsonpath='{.data.default\.credential}' | base64 -d \
    | venv/bin/python -c "import json,sys;print((json.load(sys.stdin).get('oauth') or {}).get('refreshToken','')[:12])")
L=$(venv/bin/python -c "import json;print((json.load(open('$CRED')).get('oauth') or {}).get('refreshToken','')[:12])")
if [ "$S" = "$L" ]; then
  echo "✓ 校验通过（refreshToken 前12: $S）"
else
  echo "❌ 校验失败: secret=$S 本机=$L"; exit 2
fi
echo
echo "提示：新建 Pod 才会挂载新 secret——如需让运行中的画像/训练生效，请重启对应 Pod。"
