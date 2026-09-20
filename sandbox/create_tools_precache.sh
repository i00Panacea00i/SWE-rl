#!/bin/bash
# AGS 沙箱工具批量创建（官方方法：任意镜像 + 提前预热）。
# 文档: CreateSandboxTool(CustomConfiguration) / CreatePreCacheImageTask
# 流程: 阶段1 逐镜像调用 CreatePreCacheImageTask 预热 → 阶段2 CreateSandboxTool 建工具。
# 用法: TCR_REGISTRY=<含命名空间> ROLE_ARN=<arn> bash sandbox/create_tools_precache.sh <targets.jsonl>
# targets.jsonl 每行: {"instance_id": ..., "tool_name": ..., "tag": ...}
set -uo pipefail

TCR_REGISTRY=${TCR_REGISTRY:?需设置 TCR_REGISTRY（形如 xxx.tencentcloudcr.com/swe-mirror/swe-ags）}
ROLE_ARN=${ROLE_ARN:?需设置 ROLE_ARN}
LIST=${1:?目标清单 jsonl}
REGION=${REGION:-ap-singapore}
PRECACHE_PROGRESS=${PRECACHE_PROGRESS:-/tmp/ags-precache-progress.jsonl}
TOOL_PROGRESS=${TOOL_PROGRESS:-/tmp/ags-tool-create-progress.jsonl}
touch "$PRECACHE_PROGRESS" "$TOOL_PROGRESS"

echo "=== 阶段 1/2：镜像预热（CreatePreCacheImageTask）==="
cached=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  iid=$(echo "$line" | sed -E 's/.*"instance_id": "([^"]+)".*/\1/')
  tag=$(echo "$line" | sed -E 's/.*"tag": "([^"]+)".*/\1/')
  if grep -qx "$iid" "$PRECACHE_PROGRESS"; then
    echo "[skip] $iid（已预热）"
    continue
  fi
  if tccli ags CreatePreCacheImageTask --region "$REGION" --cli-unfold-argument \
      --Image "$TCR_REGISTRY:$tag" --ImageRegistryType enterprise >/tmp/precache-out.json 2>&1; then
    digest=$(grep -oE 'sha256:[0-9a-f]+' /tmp/precache-out.json | head -1)
    echo "$iid" >> "$PRECACHE_PROGRESS"
    cached=$((cached+1))
    echo "[cached] $iid ${digest:0:19}"
  else
    echo "[FAIL] precache $iid: $(tail -1 /tmp/precache-out.json | head -c 160)"
  fi
  sleep 1
done < "$LIST"
echo "预热完成: $cached 个"

echo "=== 阶段 2/2：创建沙箱工具（CreateSandboxTool）==="
created=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  iid=$(echo "$line" | sed -E 's/.*"instance_id": "([^"]+)".*/\1/')
  tool=$(echo "$line" | sed -E 's/.*"tool_name": "([^"]+)".*/\1/')
  tag=$(echo "$line" | sed -E 's/.*"tag": "([^"]+)".*/\1/')
  if grep -qx "$iid" "$TOOL_PROGRESS"; then
    echo "[skip] $tool（已创建）"
    continue
  fi
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
    --Description "SWE-Gym $iid" >/tmp/tool-out.json 2>&1; then
    echo "$iid" >> "$TOOL_PROGRESS"
    created=$((created+1))
    echo "[created] $tool"
  else
    echo "[FAIL] $tool: $(tail -1 /tmp/tool-out.json | head -c 200)"
  fi
  sleep 1
done < "$LIST"
echo "=== 完成: 新建工具 $created 个 ==="
