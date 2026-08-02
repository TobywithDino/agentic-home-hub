$B = "http://52.10.163.115:8100"
$out = New-Object System.Collections.Generic.List[string]
$found = @{}
foreach ($st in 1..12) {
    $f = "$env:TEMP\probe_st$st.json"
    if (Test-Path $f) { Remove-Item $f }
    $code = "000"
    for ($i = 1; $i -le 4; $i++) {
        $code = curl.exe -s -m 45 -o $f -w "%{http_code}" "$B/app-api/service-types/$st/vendors"
        if ($code -ne "000") { break }
        Start-Sleep -Seconds 2
    }
    if ($code -ne "200" -or -not (Test-Path $f)) {
        $out.Add("[$code] service_type=$st  SKIP")
        continue
    }
    $raw = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    Remove-Item $f -ErrorAction SilentlyContinue
    if ($raw.Trim() -eq "" -or $raw.Trim() -eq "[]") {
        $out.Add("[$code] service_type=$st  -> 0 vendors")
        continue
    }
    $j = $raw | ConvertFrom-Json
    $n = 0
    foreach ($v in @($j)) {
        foreach ($s in @($v.matched_services)) {
            if ($s.service_vendor_id -eq 1) {
                $found[[string]$s.id] = "type=$($s.type) name=$($s.name)"
                $n++
            }
        }
    }
    $out.Add("[$code] service_type=$st  -> vendor1 services: $n")
}
$out.Add("")
$out.Add("===== vendor 1 services total: $($found.Count) =====")
foreach ($k in ($found.Keys | Sort-Object { [int]$_ })) {
    $out.Add(("  service_id={0,-4} {1}" -f $k, $found[$k]))
}
[System.IO.File]::WriteAllLines("$env:TEMP\probe_result.txt", $out, (New-Object System.Text.UTF8Encoding $false))
Write-Output "DONE"
