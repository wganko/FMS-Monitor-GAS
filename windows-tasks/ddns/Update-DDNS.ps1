# ==================================================
# Cloudflare DDNS Update Script (Robust Version)
# ==================================================

# 文字化け防止
[Console]::OutputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ★【重要】TLS 1.2 を強制有効化 (Windows Server用のおまじない)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ▼▼▼ 設定エリア (ここを書き換えてください) ▼▼▼
$ZoneId = "7f84a506292087b2931b3c9144b857fa"
$ApiToken = "aYJqYKlkzYUGr1z4QaCDC8UXu1DPzbUE74MofHQP"
$RecordName = "ant.kwgi.org"
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

# 1. 現在のグローバルIPを取得 (予備ルート付き)
$PublicIp = $null
$IpServices = @(
    "https://api.ipify.org?format=json",
    "https://ifconfig.me/ip",
    "http://checkip.dyndns.org"
)

foreach ($url in $IpServices) {
    try {
        if ($url -like "*json*") {
            $PublicIp = (Invoke-RestMethod -Uri $url -ErrorAction Stop).ip
        } else {
            # HTML系レスポンスの処理
            $raw = (Invoke-RestMethod -Uri $url -ErrorAction Stop)
            if ($raw -match '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}') {
                $PublicIp = $Matches[0]
            }
        }
        if ($PublicIp) { 
            Write-Host "Success via $url"
            break 
        }
    } catch {
        Write-Warning "Failed to connect to $url - trying next..."
    }
}

if (-not $PublicIp) {
    Write-Error "FATAL: Could not get Public IP from any source. Check internet connection or DNS."
    exit
}

Write-Host "Current Public IP: $PublicIp"

# 2. Cloudflare上の現在の登録情報を取得
$Headers = @{
    "Authorization" = "Bearer $ApiToken"
    "Content-Type"  = "application/json"
}
$ListUrl = "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records?type=A&name=$RecordName"

try {
    $RecordInfo = Invoke-RestMethod -Uri $ListUrl -Method Get -Headers $Headers -ErrorAction Stop
    if ($RecordInfo.result.Count -eq 0) {
        Write-Error "DNS Record not found: $RecordName"
        exit
    }
    $RecordId = $RecordInfo.result[0].id
    $CurrentDnsIp = $RecordInfo.result[0].content
    Write-Host "Current DNS IP:    $CurrentDnsIp"
} catch {
    Write-Error "Failed to fetch DNS record info from Cloudflare. Details: $_"
    exit
}

# 3. IPが違えば更新を実行
if ($PublicIp -ne $CurrentDnsIp) {
    Write-Host "IP has changed. Updating..."
    $UpdateUrl = "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records/$RecordId"
    $Body = @{
        type    = "A"
        name    = $RecordName
        content = $PublicIp
        ttl     = 1   
        proxied = $false 
    } | ConvertTo-Json

    try {
        $UpdateResult = Invoke-RestMethod -Uri $UpdateUrl -Method Put -Headers $Headers -Body $Body -ErrorAction Stop
        if ($UpdateResult.success) {
            Write-Host "Success! IP updated to $PublicIp"
        } else {
            Write-Error "Update failed. Cloudflare response: $($UpdateResult | ConvertTo-Json)"
        }
    } catch {
        Write-Error "Update request failed. Details: $_"
    }
} else {
    Write-Host "No change needed."
}