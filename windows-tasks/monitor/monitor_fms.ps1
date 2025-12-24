# ========================================================
# サーバー監視スクリプト (monitor_fms.ps1) - CONFIG 統一版（WPE監視/自動復旧 追加）
#  ・FMSサービス状態チェック
#  ・TCPレベルで 443 ポート疎通確認
#  ・Windows証明書ストアから ant.kwgi.org の証明書期限を取得
#  ・WPE(127.0.0.1:8989) LISTEN 監視 → 異常時は自動で Web 公開エンジン再起動（fmsadmin restart wpe）
#  ・判定ステップを 4 段階でメッセージ化
#  ・結果をコンソール表示 ＋ GAS に送信
#
#  【Status設計】
#   - INFO      : すべて正常
#   - ERROR     : 異常（復旧できなかった/サービス停止/443不可/SSL期限など）
#   - RECOVERED : 異常検知→自動復旧成功（復旧成功も異常イベントとして通知対象）
# ========================================================

# 文字化け防止
[Console]::OutputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# ----------------------------------------
# TLS 1.2 / 1.3 を有効化（GAS への HTTPS 通信のため）
# ----------------------------------------
[Net.ServicePointManager]::SecurityProtocol =
    [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# ========================================================
# CONFIG エリア（ここだけ修正すればよい）
# ========================================================
$CONFIG = [ordered]@{
    # ★ GAS Web アプリの URL
    GasUrl       = "https://script.google.com/macros/s/AKfycbw-bzoIfdcAVR2XIex0kEQMpBTB1hTvfsBDFlBgnBF6WwHA2anHk_1dLFSgWnPDwbUd/exec"

    # ★ サーバー名（GAS 側の server 列に入る値）
    ServerName   = "ant.kwgi.org"

    # ★ ant の IPアドレス（スプレッドシートの IP 列に出す値）
    ServerIp     = "192.168.3.15"

    # ★ 監視対象 FMS のホスト名（証明書 CN と一致している前提）
    FmsHost      = "ant.kwgi.org"

    # ★ FMS サービス名（Windows サービス名）
    ServiceName  = "FileMaker Server"

    # ★ TCP 監視ポート（通常 443）
    Port443      = 443

    # ★ SSL 残り日数しきい値（INFO / ERROR 判定用）
    SslWarnDays  = 30   # 30 日未満で ERROR（あなたの運用ポリシーに合わせて調整可）

    # ★ WPE 監視（127.0.0.1:8989）
    WpePort          = 8989
    WpeRestartWaitSec = 20  # WPE 再起動後の待機秒（環境により調整）

    # ★ fmsadmin.exe のパス（環境に合わせて）
    # 例: "C:\Program Files\FileMaker\FileMaker Server\Database Server\fmsadmin.exe"
    FmsAdminPath     = "C:\Program Files\FileMaker\FileMaker Server\Database Server\fmsadmin.exe"

    # ★ fmsadmin の管理者（WPE再起動用）
    # ※セキュリティを重視するなら資格情報マネージャー等に移行するのが理想ですが、まずは運用優先で定数化
    FmsAdminUser     = "chief"       # ←変更
    FmsAdminPass     = "Sasaeai;0139"    # ←変更

    # ★ ローカルログ（“復旧した事実”を残す）
    LogDir           = "C:\Logs\FMSMonitor"
    LogFileName      = "monitor_fms_ant.log"
}

# ========================================================
# ログ出力関数（ローカルファイルへ）
# ========================================================
function Write-LocalLog([string]$Level, [string]$Msg) {
    try {
        if (!(Test-Path $CONFIG.LogDir)) {
            New-Item -ItemType Directory -Path $CONFIG.LogDir | Out-Null
        }
        $logPath = Join-Path $CONFIG.LogDir $CONFIG.LogFileName
        $ts = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
        Add-Content -Path $logPath -Value "[$ts][$Level] $Msg"
    } catch {
        # ログ書き込み失敗は監視自体を止めない（最後にコンソールへ出す）
        Write-Host "ローカルログ書き込み失敗: $($_.Exception.Message)"
    }
}

# ========================================================
# WPE(8989) LISTEN 判定
# ========================================================
function Test-LocalListeningPort([int]$Port) {
    # LISTENING 行があるかどうかで判定（Windowsで安定）
    $hit = netstat -ano | Select-String -Pattern (":$Port\s+.*LISTENING")
    return ($null -ne $hit)
}

# ========================================================
# WPE 再起動（fmsadmin restart wpe）
# ========================================================
function Restart-Wpe() {
    if (!(Test-Path $CONFIG.FmsAdminPath)) {
        throw "fmsadmin.exe が見つかりません: $($CONFIG.FmsAdminPath)"
    }

    # -y : 確認なし
    $args = @(
        "restart", "wpe",
        "-u", $CONFIG.FmsAdminUser,
        "-p", $CONFIG.FmsAdminPass,
        "-y"
    )

    Write-LocalLog "WARN" "WPE再起動実行: $($CONFIG.FmsAdminPath) $($args -join ' ')"

    $p = Start-Process -FilePath $CONFIG.FmsAdminPath `
                       -ArgumentList $args `
                       -Wait -PassThru -NoNewWindow

    if ($p.ExitCode -ne 0) {
        throw "WPE再起動に失敗しました（ExitCode=$($p.ExitCode)）。"
    }
}

# ========================================================
# 変数の初期化
# ========================================================
$Status        = "INFO"       # 全体ステータス（INFO / ERROR / RECOVERED）
$ExpiryString  = ""           # GAS に送る用の有効期限文字列
$DaysLeft      = 3650         # 残り日数の初期値（暫定）

$MsgService    = ""           # 【1/4 サービス】用メッセージ
$MsgWeb        = ""           # 【2/4 TCP】用メッセージ
$MsgExpiry     = ""           # 【3/4 SSL】用メッセージ
$MsgWpe        = ""           # 【4/4 WPE】用メッセージ

$JudgeStep     = "すべて正常" # どの段階で問題になったか（サービス / TCP / SSL / WPE）

# WPE復旧フラグ（復旧成功は“異常イベント”として扱う）
$WpeRecovered  = $false

# ========================================================
# 1. FMSサービス監視（【1/4 サービス】）
# ========================================================
try {
    $ServiceStatus = Get-Service -Name $CONFIG.ServiceName -ErrorAction Stop

    if ($ServiceStatus.Status -eq 'Running') {
        $MsgService = "【1/4 サービス】FMSサービス: 稼働中"
    } else {
        $MsgService = "【1/4 サービス】?? FMSサービスが稼働していません (状態: $($ServiceStatus.Status))"
        $Status     = "ERROR"
        $JudgeStep  = "サービス"
    }
}
catch {
    $MsgService = "【1/4 サービス】?? FMSサービス状態取得に失敗: $($_.Exception.Message)"
    $Status     = "ERROR"
    $JudgeStep  = "サービス"
}

# ========================================================
# 2. TCPレベルで 443 ポート疎通確認（【2/4 TCP】）
# ========================================================
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $tcpClient.Connect($CONFIG.FmsHost, $CONFIG.Port443)
    $tcpClient.Close()

    $MsgWeb = "【2/4 TCP】Webポート$($CONFIG.Port443): 接続成功 (TCPレベル)"
}
catch {
    $MsgWeb  = "【2/4 TCP】?? Webポート$($CONFIG.Port443): 接続失敗 (TCPレベル) - $($_.Exception.Message)"
    $Status  = "ERROR"
    if ($JudgeStep -eq "すべて正常") { $JudgeStep = "TCP" }
}

# ========================================================
# 3. Windows 証明書ストアから ant.kwgi.org の証明書期限を取得（【3/4 SSL】）
# ========================================================
try {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)

    $candidates = $store.Certificates | Where-Object {
        $_.Subject -like "*CN=$($CONFIG.FmsHost)*"
    }

    if (-not $candidates -or $candidates.Count -eq 0) {
        $store.Close()
        throw "証明書ストア(LocalMachine\My)に CN=$($CONFIG.FmsHost) の証明書が見つかりませんでした。"
    }

    $now = Get-Date
    $validCandidates = $candidates | Where-Object { $_.NotAfter -gt $now }

    if (-not $validCandidates -or $validCandidates.Count -eq 0) {
        $ServerCert = $candidates | Sort-Object NotAfter -Descending | Select-Object -First 1
    } else {
        $ServerCert = $validCandidates | Sort-Object NotAfter -Descending | Select-Object -First 1
    }

    $store.Close()

    $ExpiryDate = $ServerCert.NotAfter
    $ExpiryDateOnly = $ExpiryDate.Date
    $TodayDateOnly  = (Get-Date).Date
    $DaysLeft = ($ExpiryDateOnly - $TodayDateOnly).Days
    $ExpiryDateText = $ExpiryDateOnly.ToString("yyyy/MM/dd")

    if ($DaysLeft -lt $CONFIG.SslWarnDays) {
        $MsgExpiry = "【3/4 SSL】?? 期限まで残り ${DaysLeft}日 [$ExpiryDateText]"
        $Status    = "ERROR"
        if ($JudgeStep -eq "すべて正常") { $JudgeStep = "SSL期限" }
    } else {
        $MsgExpiry = "【3/4 SSL】SSL期限: ${DaysLeft}日 (OK) [$ExpiryDateText]"
    }

    $ExpiryString = $ExpiryDateOnly.ToString("yyyy-MM-dd HH:mm:ss")
}
catch {
    $MsgExpiry = "【3/4 SSL】期限チェック失敗: $($_.Exception.Message)"
    $Status    = "ERROR"
    if ($JudgeStep -eq "すべて正常") { $JudgeStep = "SSL期限" }
}

# ========================================================
# 4. WPE(8989) 監視 → 異常なら自動復旧（【4/4 WPE】）
# ========================================================
try {
    $port = [int]$CONFIG.WpePort

    if (Test-LocalListeningPort -Port $port) {
        $MsgWpe = "【4/4 WPE】WPE(127.0.0.1:$port): LISTEN 正常"
    } else {
        # 異常検知 → 自動復旧を試行
        $MsgWpe = "【4/4 WPE】?? WPE(127.0.0.1:$port): LISTEN なし → 自動復旧を試行します"
        Write-LocalLog "WARN" "WPE異常検知: 127.0.0.1:$port LISTENなし"

        Restart-Wpe
        Start-Sleep -Seconds $CONFIG.WpeRestartWaitSec

        if (Test-LocalListeningPort -Port $port) {
            $WpeRecovered = $true
            $MsgWpe = "【4/4 WPE】!! WPE異常検知 → 自動復旧成功（127.0.0.1:$port LISTEN復帰）"
            Write-LocalLog "WARN" "WPE自動復旧成功: 127.0.0.1:$port LISTEN復帰"
            if ($JudgeStep -eq "すべて正常") { $JudgeStep = "WPE(復旧)" }
        } else {
            $MsgWpe = "【4/4 WPE】?? WPE異常: 自動復旧失敗（127.0.0.1:$port LISTENなしのまま）"
            Write-LocalLog "ERROR" "WPE自動復旧失敗: 127.0.0.1:$port LISTENなし"
            $Status = "ERROR"
            if ($JudgeStep -eq "すべて正常") { $JudgeStep = "WPE" }
        }
    }
}
catch {
    $MsgWpe = "【4/4 WPE】WPEチェック/復旧処理で例外: $($_.Exception.Message)"
    Write-LocalLog "ERROR" "WPEチェック/復旧処理例外: $($_.Exception.Message)"
    $Status = "ERROR"
    if ($JudgeStep -eq "すべて正常") { $JudgeStep = "WPE" }
}

# ========================================================
# Status 最終決定
#  - すでに ERROR なら ERROR
#  - ERROR ではなく、WPEが自動復旧したなら RECOVERED（異常イベントとして通知）
# ========================================================
if ($Status -ne "ERROR" -and $WpeRecovered) {
    $Status = "RECOVERED"
}

# ========================================================
# コンソール表示（判定ステップ＋4段階メッセージ）
# ========================================================
$Header  = "◆判定ステップ: $JudgeStep"
$Message = @(
    $Header
    $MsgService
    $MsgWeb
    $MsgExpiry
    $MsgWpe
) -join "`n"

Write-Host $Message
Write-LocalLog $Status $Message

# ========================================================
# GASへ報告送信
# ========================================================
$PayloadObject = [ordered]@{
    server           = $CONFIG.ServerName
    status           = $Status
    message          = $Message
    ip               = $CONFIG.ServerIp
    expiryDateString = $ExpiryString
}

$PayloadJson = $PayloadObject | ConvertTo-Json -Compress
$Headers = @{ "Content-Type" = "application/json; charset=utf-8" }

try {
    $resp = Invoke-RestMethod -Uri $CONFIG.GasUrl `
                              -Method Post `
                              -Body $PayloadJson `
                              -Headers $Headers `
                              -ContentType "application/json; charset=utf-8"
    Write-Host "GAS response: $resp"
    Write-Host "Report Sent: $Status"
}
catch {
    Write-Host "Failed to send report: $($_.Exception.Message)"
    Write-LocalLog "ERROR" "GAS送信失敗: $($_.Exception.Message)"
}
