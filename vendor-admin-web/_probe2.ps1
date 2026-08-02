$B = "http://52.10.163.115:8100"
$out = New-Object System.Collections.Generic.List[string]

function Try-Patch($label, $bodyJson) {
    $bf = "$env:TEMP\pb2.json"
    [System.IO.File]::WriteAllText($bf, $bodyJson, (New-Object System.Text.UTF8Encoding $false))
    $rf = "$env:TEMP\pr2.json"
    if (Test-Path $rf) { Remove-Item $rf }
    $code = "000"
    for ($i = 1; $i -le 4; $i++) {
        $code = curl.exe -s -m 60 -o $rf -w "%{http_code}" -X PATCH -H "Content-Type: application/json" --data-binary "@$bf" "$B/merchant-api/forms/13"
        if ($code -ne "000") { break }
        Start-Sleep -Seconds 3
    }
    $body = if (Test-Path $rf) { [System.IO.File]::ReadAllText($rf, [System.Text.Encoding]::UTF8) } else { "" }
    $script:out.Add("--- $label -> HTTP=$code")
    if ($body.Length -gt 0) {
        try {
            $j = $body | ConvertFrom-Json
            $script:out.Add("    feature = " + ($j.feature | ConvertTo-Json -Compress))
            $script:out.Add("    service_id present = " + ($null -ne $j.service_id))
            $script:out.Add("    top keys = " + (($j.PSObject.Properties.Name) -join ','))
        } catch {
            $script:out.Add("    raw = " + $body.Substring(0, [Math]::Min(220, $body.Length)))
        }
    }
    Remove-Item $bf, $rf -ErrorAction SilentlyContinue
}

# 測試 1: feature 放 JSON 物件
Try-Patch "feature as object" '{"form":{"feature":{"service_id":4}},"upd_id":"019fb652-df72-7992-989e-f456194edf8c"}'

# 測試 2: feature 放 JSON 字串
Try-Patch "feature as string" '{"form":{"feature":"{\"service_id\":4}"},"upd_id":"019fb652-df72-7992-989e-f456194edf8c"}'

# 測試 3: 直接送 service_id 看後端是否接受
Try-Patch "direct service_id" '{"form":{"service_id":4},"upd_id":"019fb652-df72-7992-989e-f456194edf8c"}'

[System.IO.File]::WriteAllLines("$env:TEMP\probe2_result.txt", $out, (New-Object System.Text.UTF8Encoding $false))
Write-Output "DONE"
