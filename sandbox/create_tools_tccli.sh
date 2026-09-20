#!/bin/bash
# tccli 批量创建 12 个 AGS 沙箱工具 + 提交镜像预热任务
#
# 前置（一次性）：
#   pip install -U tccli            # 需含 ags 2025-09-20（3.1.164.1+）
#   tccli configure set secretId <你的SecretId> secretKey <你的SecretKey>
#   tccli configure set region ap-singapore
#
# 用法：
#   bash sandbox/create_tools_tccli.sh            # 创建工具 + 提交预热
#   bash sandbox/create_tools_tccli.sh precache   # 仅提交预热
#   bash sandbox/create_tools_tccli.sh check      # 查询预热状态
set -uo pipefail

REGION=${REGION:-ap-singapore}
REGISTRY=${TCR_REGISTRY:-tcr.example.com/swe-mirror/swe-ags}
# 上个项目验证过的 TCR 拉取角色（务必核对实际绑定的 RoleArn）
ROLE_ARN=${ROLE_ARN:-<your-role-arn>}
NETWORK=${NETWORK:-SANDBOX}          # SANDBOX=全隔离(测试离线，推荐)；PUBLIC=需出网时改
CPU=${CPU:-1}
MEMORY=${MEMORY:-2Gi}
STORAGE=${STORAGE:-10Gi}

# tool_name|image_tag 列表（与 data/instances.jsonl 一致）
TOOLS=(
  "swe-astropy-12057|astropy_1776_astropy-12057"
  "swe-astropy-12907|astropy_1776_astropy-12907"
  "swe-django-10939|django_1776_django-10939"
  "swe-django-11039|django_1776_django-11039"
  "swe-django-12286|django_1776_django-12286"
  "swe-matplotlib-13859|matplotlib_1776_matplotlib-13859-r2"
  "swe-requests-1327|psf_1776_requests-1327"
  "swe-pylint-4551|pylint-dev_1776_pylint-4551"
  "swe-scikit-learn-10198|scikit-learn_1776_scikit-learn-10198"
  "swe-sphinx-10021|sphinx-doc_1776_sphinx-10021"
  "swe-sympy-11232|sympy_1776_sympy-11232"
  "swe-sympy-11384|sympy_1776_sympy-11384"
)

create_one() {
  local name=$1 tag=$2
  echo "=== create ${name} (${tag}) ==="
  tccli ags CreateSandboxTool --region "$REGION" --cli-unfold-argument \
    --ToolName "$name" \
    --ToolType custom \
    --NetworkConfiguration.NetworkMode "$NETWORK" \
    --CustomConfiguration.Image "${REGISTRY}:${tag}" \
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
    --CustomConfiguration.Resources.CPU "$CPU" \
    --CustomConfiguration.Resources.Memory "$MEMORY" \
    --CustomConfiguration.Resources.Storage "$STORAGE" \
    --RoleArn "$ROLE_ARN" \
    --DefaultTimeout 1h \
    --Description "SWE-bench ${tag}"
}

precache_one() {
  local tag=$1
  echo "=== precache ${tag} ==="
  tccli ags CreatePreCacheImageTask --region "$REGION" --cli-unfold-argument \
    --Image "${REGISTRY}:${tag}" \
    --ImageRegistryType enterprise
}

check_one() {
  local tag=$1 digest=$2
  tccli ags DescribePreCacheImageTask --region "$REGION" --cli-unfold-argument \
    --Image "${REGISTRY}:${tag}" --ImageDigest "$digest"
}

case "${1:-all}" in
  precache)
    for t in "${TOOLS[@]}"; do precache_one "${t#*|}"; done ;;
  check)
    # 用法: bash create_tools_tccli.sh check <tag> <digest>
    check_one "$2" "$3" ;;
  all)
    for t in "${TOOLS[@]}"; do
      IFS='|' read -r name tag <<< "$t"
      create_one "$name" "$tag"
      sleep 1   # API 限频 20次/s，保守间隔
      precache_one "$tag"
    done ;;
  *)
    echo "用法: $0 [all|precache|check <tag> <digest>]"; exit 1 ;;
esac
