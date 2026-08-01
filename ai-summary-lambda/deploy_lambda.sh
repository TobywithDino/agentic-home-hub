#!/usr/bin/env bash
# deploy_lambda.sh
# 打包並部署 AI Review Summary Lambda 到 AWS（us-west-2）
#
# 前置條件：
#   1. aws configure --profile agentic-home-hub （和 bff_server 共用同一組憑證）
#   2. Python 3.12（Lambda runtime 對應版本）
#   3. Lambda function 尚未建立的話，先執行：bash deploy_lambda.sh --create
#
# 使用方式：
#   bash deploy_lambda.sh           # 更新現有 Lambda（只更新程式碼）
#   bash deploy_lambda.sh --create  # 第一次佈署（建立 Lambda + IAM Role + EventBridge）

set -euo pipefail

# ── 載入設定 ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.deploy.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "找不到 $CONFIG_FILE"
  echo "請先執行： cp ai-summary-lambda/.deploy.env.example ai-summary-lambda/.deploy.env 並填入實際值"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${AWS_PROFILE:?.deploy.env 缺少 AWS_PROFILE}"
: "${AWS_REGION:?.deploy.env 缺少 AWS_REGION}"
: "${S3_BUCKET:?.deploy.env 缺少 S3_BUCKET}"
: "${BFF_BASE_URL:?.deploy.env 缺少 BFF_BASE_URL}"
: "${BEDROCK_MODEL_ID:?.deploy.env 缺少 BEDROCK_MODEL_ID}"

FUNCTION_NAME="${FUNCTION_NAME:-aiwave-review-summary}"
RUNTIME="python3.12"
HANDLER="handler.lambda_handler"
TIMEOUT="${TIMEOUT:-300}"
MEMORY="${MEMORY:-256}"
BEDROCK_REGION="${BEDROCK_REGION:-$AWS_REGION}"
MAX_TOKENS="${MAX_TOKENS:-2048}"
S3_KEY="lambda/${FUNCTION_NAME}.zip"

BUILD_DIR="${SCRIPT_DIR}/.build"
ZIP_PATH="${SCRIPT_DIR}/lambda_package.zip"

# ── 打包 ───────────────────────────────────────────────────────────────────────
echo "▶ Building package..."
rm -rf "${BUILD_DIR}" "${ZIP_PATH}"
mkdir -p "${BUILD_DIR}"

# 安裝依賴到 build 目錄（boto3 在 Lambda 環境內建，但固定版本比較安全）
pip install -r "${SCRIPT_DIR}/requirements.txt" \
    --target "${BUILD_DIR}" \
    --quiet

# 複製 Lambda 程式碼
cp "${SCRIPT_DIR}/handler.py" "${BUILD_DIR}/"
cp "${SCRIPT_DIR}/prompts.py" "${BUILD_DIR}/"

# 建立 zip（用 Python zipfile，不依賴 zip 指令，相容 Windows/Linux）
echo "   Zipping with Python..."
python - "${BUILD_DIR}" "${ZIP_PATH}" <<'PYEOF'
import zipfile, os, sys

build_dir = sys.argv[1]
zip_path  = sys.argv[2]

with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(build_dir):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for file in files:
            if file.endswith(".pyc"):
                continue
            abs_path = os.path.join(root, file)
            arc_name = os.path.relpath(abs_path, build_dir)
            zf.write(abs_path, arc_name)

print(f"   Zip created: {zip_path} ({os.path.getsize(zip_path) // 1024} KB)")
PYEOF

# ── 上傳 S3 ────────────────────────────────────────────────────────────────────
echo "▶ Uploading to S3..."
aws s3 cp "${ZIP_PATH}" "s3://${S3_BUCKET}/${S3_KEY}" \
    --profile "${AWS_PROFILE}" \
    --region "${AWS_REGION}"

# ── 首次建立 or 更新程式碼 ──────────────────────────────────────────────────────
if [[ "${1:-}" == "--create" ]]; then
    echo "▶ Creating IAM role..."

    # 建立 Lambda execution role（若已存在則略過）
    ROLE_NAME="${FUNCTION_NAME}-role"
    TRUST_POLICY='{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "Service": "lambda.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }]
    }'

    ROLE_ARN=$(aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document "${TRUST_POLICY}" \
        --profile "${AWS_PROFILE}" \
        --query "Role.Arn" \
        --output text 2>/dev/null || \
        aws iam get-role \
            --role-name "${ROLE_NAME}" \
            --profile "${AWS_PROFILE}" \
            --query "Role.Arn" \
            --output text)

    # 附加所需 policy（CloudWatch Logs + Bedrock）
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        --profile "${AWS_PROFILE}" 2>/dev/null || true

    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonBedrockFullAccess" \
        --profile "${AWS_PROFILE}" 2>/dev/null || true

    echo "   Role ARN: ${ROLE_ARN}"
    echo "   Waiting 10s for IAM propagation..."
    sleep 10

    echo "▶ Creating Lambda function..."
    aws lambda create-function \
        --function-name "${FUNCTION_NAME}" \
        --runtime "${RUNTIME}" \
        --handler "${HANDLER}" \
        --role "${ROLE_ARN}" \
        --code "S3Bucket=${S3_BUCKET},S3Key=${S3_KEY}" \
        --timeout "${TIMEOUT}" \
        --memory-size "${MEMORY}" \
        --environment "Variables={
            BFF_BASE_URL=${BFF_BASE_URL},
            BEDROCK_MODEL_ID=${BEDROCK_MODEL_ID},
            BEDROCK_REGION=${BEDROCK_REGION},
            MAX_TOKENS=${MAX_TOKENS}
        }" \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}"

    # ── 建立 Function URL（讓你用 curl 手動觸發，不需要 API Gateway）────────────
    echo "▶ Creating Function URL (for manual/demo invocation)..."
    FUNCTION_URL=$(aws lambda create-function-url-config \
        --function-name "${FUNCTION_NAME}" \
        --auth-type NONE \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}" \
        --query "FunctionUrl" \
        --output text)

    # Function URL 需要加一條 resource-based policy 才能公開存取
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id "AllowPublicFunctionUrl" \
        --action "lambda:InvokeFunctionUrl" \
        --principal "*" \
        --function-url-auth-type NONE \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}" > /dev/null

    echo ""
    echo "✅ Lambda created!"
    echo "   Function URL: ${FUNCTION_URL}"
    echo "   （存到 README 方便 demo 時 curl）"

    # ── 建立 EventBridge 每週排程 ───────────────────────────────────────────────
    echo "▶ Creating EventBridge weekly schedule..."
    FUNCTION_ARN=$(aws lambda get-function \
        --function-name "${FUNCTION_NAME}" \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}" \
        --query "Configuration.FunctionArn" \
        --output text)

    # 每週一 UTC 01:00（台灣時間週一 09:00）
    RULE_NAME="${FUNCTION_NAME}-weekly"
    aws events put-rule \
        --name "${RULE_NAME}" \
        --schedule-expression "cron(0 1 ? * MON *)" \
        --state ENABLED \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}" > /dev/null

    aws events put-targets \
        --rule "${RULE_NAME}" \
        --targets "Id=1,Arn=${FUNCTION_ARN}" \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}" > /dev/null

    # 讓 EventBridge 有權限呼叫 Lambda
    aws lambda add-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id "AllowEventBridgeWeekly" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:$(aws sts get-caller-identity --profile ${AWS_PROFILE} --query Account --output text):rule/${RULE_NAME}" \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}" > /dev/null

    echo "   EventBridge rule created: ${RULE_NAME} (每週一 09:00 台灣時間)"

else
    echo "▶ Updating Lambda code..."
    aws lambda update-function-code \
        --function-name "${FUNCTION_NAME}" \
        --s3-bucket "${S3_BUCKET}" \
        --s3-key "${S3_KEY}" \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}" \
        --query "FunctionArn" \
        --output text

    echo "▶ Waiting for update to complete..."
    aws lambda wait function-updated \
        --function-name "${FUNCTION_NAME}" \
        --region "${AWS_REGION}" \
        --profile "${AWS_PROFILE}"

    echo "✅ Lambda code updated: ${FUNCTION_NAME}"
fi

# ── 清理 ────────────────────────────────────────────────────────────────────────
rm -rf "${BUILD_DIR}" "${ZIP_PATH}"
echo "▶ Cleaned up build artifacts."
