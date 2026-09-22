# Re-applies the charge limit last chosen in the GUI.
# Runs headless via the scheduled task "FrameworkBatteryLimit-Apply".
#
# The EC keeps the limit in its own RAM and loses it whenever it is power cycled -
# that is not only a cold boot but also a resume from sleep. The task therefore
# fires at logon, on unlock, after every resume and (as a net) periodically.

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

# Reads the maximum from "framework_tool --charge-limit". Returns $null if the EC
# did not answer usefully - right after a resume it is sometimes busy for a moment.
function Get-Limit {
    $out = (& $exe --charge-limit 2>&1 | Out-String)
    if ($out -match 'Maximum\s+(\d+)\s*%') { [int]$Matches[1] } else { $null }
}

try {
    if (-not (Test-Path $store)) { Write-Log 'no limit.txt - nothing to do'; exit 0 }
    if (-not (Test-Path $exe))   { Write-Log "framework_tool.exe missing: $exe"; exit 1 }

    $raw = (Get-Content -Path $store -Raw).Trim()
    if ($raw -notmatch '^\d{1,3}$') { Write-Log "limit.txt unusable: '$raw'"; exit 1 }
    $want = [int]$raw
    if ($want -lt 20 -or $want -gt 100) { Write-Log "value outside 20-100: $want"; exit 1 }

    # After a resume the EC can need a few seconds before it talks to us.
    $cur = $null
    foreach ($try in 1..5) {
        $cur = Get-Limit
        if ($null -ne $cur) { break }
        Start-Sleep -Seconds 3
    }
    if ($null -eq $cur) { Write-Log 'EC did not report a limit after 5 tries'; exit 1 }

    # Silent in the common case, otherwise the periodic run would flood the log.
    if ($cur -eq $want) { exit 0 }

    $now = $null
    foreach ($try in 1..3) {
        (& $exe --charge-limit "$want" 2>&1) | Out-Null
        $now = Get-Limit
        if ($now -eq $want) { break }
        Start-Sleep -Seconds 3
    }

    if ($now -eq $want) {
        Write-Log "limit $cur % -> $want % applied"
        exit 0
    } else {
        Write-Log "failed to apply (was $cur %, wanted $want %, EC now reports '$now')"
        exit 1
    }
} catch {
    Write-Log "ERROR: $_"
    exit 1
}
