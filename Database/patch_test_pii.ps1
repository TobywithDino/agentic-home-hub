# -*- coding: utf-8 -*-
# 補寫測試帳號個資明文（AES-256-GCM 加密欄位）
#
# 前提：PII_ENCRYPTION_KEY_B64 必須已在 EC2 的 .env 設定好，且 aiwave-api 已重啟。
# 若金鑰尚未設定，這裡的 PATCH 會成功執行但 contact_name/contact_mobile/contact_email
# 依然會存成 NULL（encrypt_pii 短路），等於白做一次，執行前請先確認金鑰狀態。
#
# 用法：
#   powershell -File patch_test_pii.ps1
#   或指定 api_server base url： powershell -File patch_test_pii.ps1 -BaseUrl "http://52.10.163.115:8000"

param(
    [string]$BaseUrl = "http://52.10.163.115:8000"
)

$ErrorActionPreference = "Stop"

function Patch-Json($url, $bodyObj) {
    $json = $bodyObj | ConvertTo-Json -Compress -Depth 5
    $tmp = New-TemporaryFile
    [System.IO.File]::WriteAllText($tmp.FullName, $json, [System.Text.Encoding]::UTF8)
    try {
        $resp = curl.exe -s -X PATCH $url -H "Content-Type: application/json" --data-binary "@$($tmp.FullName)"
        Write-Output $resp
    } finally {
        Remove-Item $tmp.FullName -Force
    }
}

Write-Host "=== 補寫 user_accounts 測試個資 ===" -ForegroundColor Cyan

# user01@example.com
Patch-Json "$BaseUrl/users/019c0464-2d01-73f0-9f9b-d1392fdb941a" @{
    contact_name   = "測試會員01"
    contact_mobile = "0912000001"
    contact_email  = "user01@example.com"
}
Write-Host ""

# user02@example.com
Patch-Json "$BaseUrl/users/019eee3f-841e-7048-ae67-0955b144f4f8" @{
    contact_name   = "測試會員02"
    contact_mobile = "0912000002"
    contact_email  = "user02@example.com"
}
Write-Host ""

# user03@example.com
Patch-Json "$BaseUrl/users/019a52d3-7f6b-7a51-a53a-3c365f741b49" @{
    contact_name   = "測試會員03"
    contact_mobile = "0912000003"
    contact_email  = "user03@example.com"
}
Write-Host ""

# user04@example.com
Patch-Json "$BaseUrl/users/019fb652-df76-7490-bc44-2bc5d255512f" @{
    contact_name   = "測試會員04"
    contact_mobile = "0912000004"
    contact_email  = "user04@example.com"
}
Write-Host ""

Write-Host "=== 補寫 vendor_accounts 測試個資 ===" -ForegroundColor Cyan

# vendor01@example.com (service_vendor_id=1)
Patch-Json "$BaseUrl/vendors/1/accounts/019fb652-df72-7992-989e-f456194edf8c" @{
    contact_name   = "測試商家聯絡人01"
    contact_mobile = "0987000001"
    contact_email  = "vendor01@example.com"
}
Write-Host ""

# vendor02@example.com (service_vendor_id=2)
Patch-Json "$BaseUrl/vendors/2/accounts/019fb652-df73-7214-8378-0811dffa943f" @{
    contact_name   = "測試商家聯絡人02"
    contact_mobile = "0987000002"
    contact_email  = "vendor02@example.com"
}
Write-Host ""

# vendor03@example.com (service_vendor_id=5)
Patch-Json "$BaseUrl/vendors/5/accounts/019fb652-df75-7aa4-bd53-5a067b31d124" @{
    contact_name   = "測試商家聯絡人03"
    contact_mobile = "0987000003"
    contact_email  = "vendor03@example.com"
}
Write-Host ""

Write-Host "完成。請檢查上方每筆回應的 contact_name 是否為明文（非 null）以確認金鑰生效。" -ForegroundColor Green
