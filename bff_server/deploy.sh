#!/bin/bash
# ============================================================
# BFF Server 部署腳本（在本機 Git Bash / WSL 執行）
#
# 跟舊版的差異，兩個都是實際踩到的坑：
#
#   1. PROJECT_ROOT 改成從腳本位置自動推導，不再寫死某個人的本機路徑。
#      舊版寫死隊友的目錄，導致任何人執行都是打包「他那份」工作目錄，
#      結果別人 commit 的程式碼永遠上不去（AI 管家端點就是這樣消失的）。
#
#   2. .env 改成從 .deploy.env 完整生成，不再用 `>` 覆寫成只有兩行。
#      舊版每次部署都把 AGENTCORE_RUNTIME_ARN 抹掉，AI 管家就會壞。
#
# 設定值放 bff_server/.deploy.env（不進版控），複製 .deploy.env.example 來填。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SCRIPT_DIR/.deploy.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "找不到 $CONFIG_FILE"
  echo "請先執行： cp bff_server/.deploy.env.example bff_server/.deploy.env 並填入實際值"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${AWS_PROFILE:?.deploy.env 缺少 AWS_PROFILE}"
: "${AWS_REGION:?.deploy.env 缺少 AWS_REGION}"
: "${INSTANCE_ID:?.deploy.env 缺少 INSTANCE_ID}"
: "${S3_BUCKET:?.deploy.env 缺少 S3_BUCKET}"
: "${EC2_IP:?.deploy.env 缺少 EC2_IP}"
AGENTCORE_RUNTIME_ARN="${AGENTCORE_RUNTIME_ARN:-}"
AGENTCORE_QUALIFIER="${AGENTCORE_QUALIFIER:-DEFAULT}"

AWS="aws --profile $AWS_PROFILE --region $AWS_REGION"
REMOTE_DIR="/home/ssm-user/aiwave"

echo "專案根目錄：$PROJECT_ROOT"
echo "部署目標：  $INSTANCE_ID ($EC2_IP)"
if [[ -z "$AGENTCORE_RUNTIME_ARN" ]]; then
  echo "⚠️  AGENTCORE_RUNTIME_ARN 未設定 —— AI 管家端點會回 error 事件"
fi
echo

# ------------------------------------------------------------
echo "===== Step 1/6: 檢查將要部署的內容 ====="
# 部署前先確認關鍵檔案在，避免像舊版那樣默默少打包一個新檔案
for required in \
  "bff_server/app/main.py" \
  "bff_server/app/agent_client.py" \
  "bff_server/requirements.txt"
do
  if [[ ! -f "$PROJECT_ROOT/$required" ]]; then
    echo "缺少 $required，中止"
    exit 1
  fi
done

if ! grep -q "butler/chat" "$PROJECT_ROOT/bff_server/app/routers/app_api.py"; then
  echo "⚠️  app_api.py 找不到 butler/chat 端點，你的工作目錄可能不是最新的"
  echo "    先 git pull 再重跑。"
  read -r -p "    仍要繼續嗎？(y/N) " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1
fi
echo "檔案檢查通過"

# ------------------------------------------------------------
echo
echo "===== Step 2/6: 打包 ====="
TARBALL="$(mktemp -t bff_deploy.XXXXXX).tar.gz"
tar -czf "$TARBALL" -C "$PROJECT_ROOT" \
  --exclude='__pycache__' \
  --exclude='*.pyc' \
  --exclude='.env' \
  --exclude='.deploy.env' \
  bff_server
echo "打包完成：$TARBALL ($(du -h "$TARBALL" | cut -f1))"

# ------------------------------------------------------------
echo
echo "===== Step 3/6: 上傳 S3 ====="
$AWS s3 cp "$TARBALL" "s3://$S3_BUCKET/bff_deploy.tar.gz"
rm -f "$TARBALL"

# ------------------------------------------------------------
echo
echo "===== Step 4/6: 在 EC2 上解壓、裝依賴、重啟 ====="

# .env 一次寫完整份。舊版用 `>` 只寫兩行，會把 ARN 抹掉。
ENV_LINES="DB_API_BASE_URL=http://127.0.0.1:8000\nCORS_ALLOW_ORIGINS=*\nAWS_REGION=$AWS_REGION\n"
if [[ -n "$AGENTCORE_RUNTIME_ARN" ]]; then
  ENV_LINES="${ENV_LINES}AGENTCORE_RUNTIME_ARN=$AGENTCORE_RUNTIME_ARN\nAGENTCORE_QUALIFIER=$AGENTCORE_QUALIFIER\n"
fi

SERVICE_UNIT='[Unit]\nDescription=BFF API Server\nAfter=network.target aiwave-api.service\n\n[Service]\nUser=root\nWorkingDirectory=/home/ssm-user/aiwave/bff_server\nEnvironmentFile=/home/ssm-user/aiwave/bff_server/.env\nExecStart=/home/ssm-user/aiwave/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8100 --workers 2\nRestart=always\n\n[Install]\nWantedBy=multi-user.target\n'

COMMANDS=$(cat <<JSON
[
  "set -e",
  "cd $REMOTE_DIR",
  "aws s3 cp s3://$S3_BUCKET/bff_deploy.tar.gz . --region $AWS_REGION",
  "tar -xzf bff_deploy.tar.gz",
  "rm -f bff_deploy.tar.gz",
  "source venv/bin/activate",
  "pip install --quiet -r bff_server/requirements.txt",
  "printf '$ENV_LINES' > bff_server/.env",
  "printf '$SERVICE_UNIT' > /etc/systemd/system/bff-api.service",
  "systemctl daemon-reload",
  "systemctl enable bff-api",
  "systemctl restart bff-api",
  "sleep 4",
  "systemctl is-active bff-api",
  "python -c \\"import boto3; print('boto3', boto3.__version__)\\"",
  "curl -s http://127.0.0.1:8100/health"
]
JSON
)

COMMAND_ID=$($AWS ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "{\"commands\":$COMMANDS}" \
  --query "Command.CommandId" --output text)

echo "CommandId: $COMMAND_ID"
echo -n "等待執行"
for _ in $(seq 1 30); do
  STATUS=$($AWS ssm get-command-invocation \
    --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
    --query "Status" --output text 2>/dev/null || echo "Pending")
  case "$STATUS" in
    Success) echo " → Success"; break ;;
    Failed|Cancelled|TimedOut) echo " → $STATUS"; break ;;
    *) echo -n "."; sleep 3 ;;
  esac
done

echo
echo "--- EC2 上的輸出 ---"
$AWS ssm get-command-invocation \
  --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
  --query "StandardOutputContent" --output text

ERR=$($AWS ssm get-command-invocation \
  --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
  --query "StandardErrorContent" --output text)
if [[ -n "$ERR" && "$ERR" != "None" ]]; then
  echo "--- stderr ---"
  echo "$ERR"
fi

if [[ "$STATUS" != "Success" ]]; then
  echo "部署失敗，中止後續驗證"
  exit 1
fi

# ------------------------------------------------------------
echo
echo "===== Step 5/6: 確認安全群組開了 8100 ====="
SG_ID=$($AWS ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" --output text)
$AWS ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" --protocol tcp --port 8100 --cidr "0.0.0.0/0" \
  >/dev/null 2>&1 && echo "已新增 8100 規則" || echo "8100 規則已存在（正常）"

# ------------------------------------------------------------
echo
echo "===== Step 6/6: 驗證端點 ====="
sleep 2
echo -n "health: "
curl -sS "http://$EC2_IP:8100/health" && echo

# 直接確認新端點真的在，而不是只看 health 就宣告成功。
# 舊版只驗 health，所以「部署成功但新端點沒上去」完全看不出來。
if curl -sS "http://$EC2_IP:8100/openapi.json" | grep -q "butler/chat"; then
  echo "✓ /app-api/butler/chat 已上線"
else
  echo "✗ /app-api/butler/chat 不在 openapi.json —— 新程式碼沒生效"
  exit 1
fi

echo
echo "===== 部署完成 ====="
echo "BFF API:    http://$EC2_IP:8100"
echo "Swagger UI: http://$EC2_IP:8100/docs"
