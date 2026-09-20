#!/bin/bash
# 为 SWE-Gym 镜像批量创建 AGS 沙箱工具（含预热）。
# 用法: TCR_REGISTRY=<真实地址> ROLE_ARN=<真实ARN> bash sandbox/create_swe_gym_tools.sh <清单.jsonl> [仅已完成镜像]
# 工具名与实例清单的 tool_name 一致（swe-<仓库>-<编号>）。
set -uo pipefail

TCR_REGISTRY=${TCR_REGISTRY:?需设置 TCR_REGISTRY}
ROLE_ARN=${ROLE_ARN:?需设置 ROLE_ARN}
LIST=${1:?实例清单 jsonl}
PROGRESS=${2:-/tmp/swe-gym-image-progress.jsonl}
REGION=${REGION:-ap-singapore}

count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  iid=$(echo "$line" | sed -E 's/.*"instance_id": "([^"]+)".*/\1/')
  tool=$(echo "$line" | sed -E 's/.*"tool_name": "([^"]+)".*/\1/')
  repo=$(echo "$line" | sed -E 's/.*"repo": "([^"]+)".*/\1/')
  tag=$(echo "$iid" | tr 'A-Z' 'a-z' | sed 's/__/_s_/g')

  if [ -f "$PROGRESS" ] && ! cut -d'"' -f4 "$PROGRESS" | grep -q "^$iid$"; then
    continue  # 镜像尚未构建完成
  fi

  echo "=== create $tool ($iid) ==="
  if tccli ags CreateSandboxTool --region "$REGION" --cli-unfold-argument \
    --ToolName "$tool" \
    --ToolType custom \
    --NetworkConfiguration.NetworkMode SANDBOX \
    --CustomConfiguration.Image "$TCR_REGISTRY:$tag" \
    --CustomConfiguration.ImageRegistryType enterprise \
    --CustomConfiguration.Command /usr/bin/envd \
    --CustomConfiguration.Ports.0.Name envd \
    --CustomConfiguration.Ports.0.Port 49983 \
    --CustomConfiguration.Ports.0.Protocol TCP \
    --CustomConfiguration.Probe.HttpGet.Path /health \
    --CustomConfiguration.Probe.HttpGet.Port 49983 \
    --CustomConfiguration.Probe.HttpGet.Scheme HTTP \
    --CustomConfiguration.Probe.ReadyTimeoutMs 30000 \
    --CustomConfiguration.Probe.ProbeTimeoutMs 3000 \
    --CustomConfiguration.Probe.ProbePeriodMs 3000 \
    --CustomConfiguration.Probe.SuccessThreshold 1 \
    --CustomConfiguration.Probe.FailureThreshold 100 \
    --CustomConfiguration.Resources.CPU 1 \
    --CustomConfiguration.Resources.Memory 2Gi \
    --CustomConfiguration.Resources.Storage 10Gi \
    --RoleArn "$ROLE_ARN" \
    --DefaultTimeout 1h \
    --Description "SWE-Gym $iid" >/dev/null 2>&1; then
    count=$((count+1))
    tccli ags CreatePreCacheImageTask --region "$REGION" --cli-unfold-argument \
      --Image "$TCR_REGISTRY:$tag" --ImageRegistryType enterprise >/dev/null 2>&1 || true
  else
    echo "[FAIL] $tool"
  fi
  sleep 1
done < "$LIST"
echo "=== 工具创建完成: $count ==="
