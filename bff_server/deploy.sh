#!/bin/bash
# ============================================================
# BFF Server 部署腳本
# 在你的本機 Git Bash / WSL 執行
# 前提：已設定好 AWS CLI profile "agentic-home-hub"
# ============================================================
set -e

PROFILE="agentic-home-hub"
REGION="us-west-2"
INSTANCE_ID="i-0a2d19c738be6cb09"
S3_BUCKET="aiwave-deploy-728259505479-uswest2"
PROJECT_ROOT="c:/Users/USER/2026Hackathon/agentic-home-hub"
EC2_IP="52.10.163.115"

echo "===== Step 1: 打包 bff_server ====="
tar -czf /tmp/bff_deploy.tar.gz -C "$PROJECT_ROOT" bff_server
echo "打包完成: /tmp/bff_deploy.tar.gz"

echo ""
echo "===== Step 2: 上傳到 S3 ====="
aws s3 cp /tmp/bff_deploy.tar.gz "s3://$S3_BUCKET/bff_deploy.tar.gz" --profile "$PROFILE" --region "$REGION"
echo "上傳完成"

echo ""
echo "===== Step 3: 送指令到 EC2（下載、安裝、啟動 service）====="
COMMAND_ID=$(aws ssm send-command \
    --profile "$PROFILE" \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters '{"commands":["cd /home/ssm-user/aiwave","aws s3 cp s3://aiwave-deploy-728259505479-uswest2/bff_deploy.tar.gz . --region us-west-2","tar -xzf bff_deploy.tar.gz","rm -f bff_deploy.tar.gz","source venv/bin/activate","pip install --quiet -r bff_server/requirements.txt","echo DB_API_BASE_URL=http://127.0.0.1:8000 > bff_server/.env","echo CORS_ALLOW_ORIGINS=* >> bff_server/.env","printf \"[Unit]\\nDescription=BFF API Server\\nAfter=network.target aiwave-api.service\\n\\n[Service]\\nUser=root\\nWorkingDirectory=/home/ssm-user/aiwave/bff_server\\nEnvironmentFile=/home/ssm-user/aiwave/bff_server/.env\\nExecStart=/home/ssm-user/aiwave/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8100 --workers 2\\nRestart=always\\n\\n[Install]\\nWantedBy=multi-user.target\\n\" > /etc/systemd/system/bff-api.service","systemctl daemon-reload","systemctl enable bff-api","systemctl restart bff-api","sleep 3","systemctl status bff-api --no-pager","curl -s http://127.0.0.1:8100/health"]}' \
    --query "Command.CommandId" \
    --output text)

echo "指令已送出，CommandId: $COMMAND_ID"

echo ""
echo "===== Step 4: 等待執行結果 ====="
echo "等待 20 秒..."
sleep 20

aws ssm get-command-invocation \
    --profile "$PROFILE" \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --output json

echo ""
echo "===== Step 5: 開放安全群組 8100 port ====="
SG_ID=$(aws ec2 describe-instances \
    --profile "$PROFILE" \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
    --output text)

echo "Security Group: $SG_ID"

aws ec2 authorize-security-group-ingress \
    --profile "$PROFILE" \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 8100 \
    --cidr "0.0.0.0/0" 2>/dev/null || echo "8100 port 規則可能已存在（正常）"

echo ""
echo "===== Step 6: 驗證 ====="
sleep 3
curl -s "http://$EC2_IP:8100/health" && echo ""

echo ""
echo "===== 部署完成 ====="
echo "BFF API:     http://$EC2_IP:8100"
echo "Swagger UI:  http://$EC2_IP:8100/docs"
echo "Health:      http://$EC2_IP:8100/health"
