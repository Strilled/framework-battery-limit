# Re-applies the charge limit last chosen in the GUI.
# Runs headless via the scheduled task "FrameworkBatteryLimit-Apply" at every logon.

$ErrorActionPreference = 'Stop'
$exe   = Join-Path $PSScriptRoot 'framework_tool.exe'
$store = Join-Path $PSScriptRoot 'limit.txt'
$log   = Join-Path $PSScriptRoot 'fw-apply.log'

function Write-Log([string]$msg) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $log -Value $line -Encoding utf8
    # Keep the log short
    $all = @(Get-Content -Path $log -Encoding utf8)
    if ($all.Count -gt 200) {
        Set-Content -Path $log -Value $all[-200..-1] -Encoding utf8
    }
}

try {
    if (-not (Test-Path $store)) { Write-Log 'no limit.txt - nothing to do'; exit 0 }
    if (-not (Test-Path $exe))   { Write-Log "framework_tool.exe missing: $exe"; exit 1 }

    $raw = (Get-Content -Path $store -Raw).Trim()
    if ($raw -notmatch '^\d{1,3}$') { Write-Log "limit.txt unusable: '$raw'"; exit 1 }
    $want = [int]$raw
    if ($want -lt 20 -or $want -gt 100) { Write-Log "value outside 20-100: $want"; exit 1 }

    $before = (& $exe --charge-limit 2>&1 | Out-String)
    $cur = if ($before -match 'Maximum\s+(\d+)\s*%') { [int]$Matches[1] } else { $null }

    if ($cur -eq $want) { Write-Log "limit already $want % - no change"; exit 0 }

    $res = (& $exe --charge-limit "$want" 2>&1 | Out-String)
    $now = if ($res -match 'Maximum\s+(\d+)\s*%') { [int]$Matches[1] } else { $null }

    if ($now -eq $want) {
        Write-Log "limit $cur % -> $want % applied"
        exit 0
    } else {
        Write-Log "failed to apply (was $cur %, wanted $want %): $($res.Trim())"
        exit 1
    }
} catch {
    Write-Log "ERROR: $_"
    exit 1
}
