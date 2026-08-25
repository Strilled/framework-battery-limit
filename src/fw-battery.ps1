# Framework battery charge limit - small WinForms GUI around framework_tool.exe
# Requires admin rights (framework_tool.exe talks to the embedded controller directly).

$ErrorActionPreference = 'Stop'
$exe      = Join-Path $PSScriptRoot 'framework_tool.exe'
$store    = Join-Path $PSScriptRoot 'limit.txt'
$taskName = 'FrameworkBatteryLimit-Apply'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Please run as administrator.`n`nThe desktop shortcut does this for you.",
        'Framework Battery', 'OK', 'Warning') | Out-Null
    exit 1
}
if (-not (Test-Path $exe)) {
    [System.Windows.Forms.MessageBox]::Show(
        "framework_tool.exe not found:`n$exe", 'Framework Battery', 'OK', 'Error') | Out-Null
    exit 1
}

function Invoke-FwTool([string[]]$fwArgs) {
    try { (& $exe @fwArgs 2>&1 | Out-String) } catch { "ERROR: $_" }
}

function Get-Status {
    $limitRaw = Invoke-FwTool @('--charge-limit')
    $powerRaw = Invoke-FwTool @('--power')

    $limit = if ($limitRaw -match 'Maximum\s+(\d+)\s*%') { [int]$Matches[1] } else { $null }
    $soc   = if ($powerRaw -match 'Charge level:\s+(\d+)\s*%') { [int]$Matches[1] } else { $null }
    $ac    = if ($powerRaw -match 'AC is:\s+(\w+)') { $Matches[1] } else { 'unknown' }

    # Charger values from the "Charger Status" block
    $mv    = if ($powerRaw -match 'Charger Voltage:\s+(\d+)\s*mV')   { [int]$Matches[1] } else { $null }
    $ma    = if ($powerRaw -match 'Charger Current:\s+(\d+)\s*mA')   { [int]$Matches[1] } else { $null }
    $inMa  = if ($powerRaw -match 'Chg Input Current:\s*(\d+)\s*mA') { [int]$Matches[1] } else { $null }
    $lfcc  = if ($powerRaw -match 'Battery LFCC:\s+(\d+)\s*mAh')     { [int]$Matches[1] } else { $null }

    $state = 'unknown'
    if     ($powerRaw -match 'Battery charging')        { $state = 'charging' }
    elseif ($powerRaw -match 'Battery discharging')     { $state = 'discharging' }
    elseif ($powerRaw -match 'Battery is:\s+connected') { $state = 'holding' }

    [pscustomobject]@{
        Limit = $limit; Soc = $soc; Ac = $ac; State = $state
        Mv = $mv; Ma = $ma; InMa = $inMa; Lfcc = $lfcc
    }
}

# ---------- UI ----------
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Framework - Battery Charge Limit'
$form.ClientSize      = New-Object System.Drawing.Size(390, 390)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.StartPosition   = 'CenterScreen'
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor       = [System.Drawing.Color]::White
try {
    $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon("$env:SystemRoot\System32\powercpl.dll")
} catch { }

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location  = New-Object System.Drawing.Point(18, 15)
$lblStatus.Size      = New-Object System.Drawing.Size(354, 24)
$lblStatus.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$lblStatus.Text      = 'Reading status ...'
$form.Controls.Add($lblStatus)

$lblDetail = New-Object System.Windows.Forms.Label
$lblDetail.Location  = New-Object System.Drawing.Point(18, 41)
$lblDetail.Size      = New-Object System.Drawing.Size(354, 20)
$lblDetail.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblDetail)

# Live charger readings
$lblCharge = New-Object System.Windows.Forms.Label
$lblCharge.Location  = New-Object System.Drawing.Point(18, 62)
$lblCharge.Size      = New-Object System.Drawing.Size(354, 20)
$lblCharge.Font      = New-Object System.Drawing.Font('Consolas', 9)
$lblCharge.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$form.Controls.Add($lblCharge)

$lblCharge2 = New-Object System.Windows.Forms.Label
$lblCharge2.Location  = New-Object System.Drawing.Point(18, 82)
$lblCharge2.Size      = New-Object System.Drawing.Size(354, 20)
$lblCharge2.Font      = New-Object System.Drawing.Font('Consolas', 9)
$lblCharge2.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblCharge2)

# Battery bar: fill level plus limit marker
$bar = New-Object System.Windows.Forms.Panel
$bar.Location  = New-Object System.Drawing.Point(18, 110)
$bar.Size      = New-Object System.Drawing.Size(354, 30)
$bar.BackColor = [System.Drawing.Color]::FromArgb(238, 238, 238)
$script:barSoc = 0
$script:barLimit = 100
$bar.Add_Paint({
    $g = $_.Graphics
    $w = $bar.Width
    $h = $bar.Height
    $fillW = [int]($w * ($script:barSoc / 100.0))
    $col = if ($script:barSoc -gt $script:barLimit) {
        [System.Drawing.Color]::FromArgb(230, 160, 60)
    } else {
        [System.Drawing.Color]::FromArgb(70, 170, 90)
    }
    $brush = New-Object System.Drawing.SolidBrush($col)
    $g.FillRectangle($brush, 0, 0, $fillW, $h)
    $brush.Dispose()
    if ($script:barLimit -lt 100) {
        $x = [int]($w * ($script:barLimit / 100.0)) - 1
        $g.FillRectangle([System.Drawing.Brushes]::Black, $x, 0, 2, $h)
    }
    $g.DrawRectangle([System.Drawing.Pens]::Silver, 0, 0, $w - 1, $h - 1)
})
$form.Controls.Add($bar)

$lblPick = New-Object System.Windows.Forms.Label
$lblPick.Location = New-Object System.Drawing.Point(18, 152)
$lblPick.Size     = New-Object System.Drawing.Size(354, 20)
$lblPick.Text     = 'New limit:'
$form.Controls.Add($lblPick)

$track = New-Object System.Windows.Forms.TrackBar
$track.Location      = New-Object System.Drawing.Point(14, 173)
$track.Size          = New-Object System.Drawing.Size(362, 45)
$track.Minimum       = 50
$track.Maximum       = 100
$track.TickFrequency = 5
$track.SmallChange   = 5
$track.LargeChange   = 10
$track.Value         = 80
$form.Controls.Add($track)

$lblVal = New-Object System.Windows.Forms.Label
$lblVal.Location  = New-Object System.Drawing.Point(18, 220)
$lblVal.Size      = New-Object System.Drawing.Size(100, 26)
$lblVal.Font      = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblVal.Text      = '80 %'
$form.Controls.Add($lblVal)
$track.Add_ValueChanged({ $lblVal.Text = "$($track.Value) %" })

# Presets
$px = 122
foreach ($p in @(60, 80, 100)) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text     = "$p %"
    $b.Location = New-Object System.Drawing.Point($px, 221)
    $b.Size     = New-Object System.Drawing.Size(80, 26)
    $b.Tag      = $p
    $b.Add_Click({ $track.Value = [int]$this.Tag })
    $form.Controls.Add($b)
    $px += 86
}

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text      = 'Apply limit'
$btnApply.Location  = New-Object System.Drawing.Point(18, 260)
$btnApply.Size      = New-Object System.Drawing.Size(180, 34)
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.FlatStyle = 'Flat'
$btnApply.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnApply)
$form.AcceptButton = $btnApply

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text     = 'Refresh'
$btnRefresh.Location = New-Object System.Drawing.Point(208, 260)
$btnRefresh.Size     = New-Object System.Drawing.Size(164, 34)
$form.Controls.Add($btnRefresh)

$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Location = New-Object System.Drawing.Point(18, 302)
$chkAuto.Size     = New-Object System.Drawing.Size(356, 22)
$chkAuto.Text     = 'Re-apply automatically at every logon'
$form.Controls.Add($chkAuto)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Location  = New-Object System.Drawing.Point(18, 328)
$lblHint.Size      = New-Object System.Drawing.Size(356, 52)
$lblHint.ForeColor = [System.Drawing.Color]::DimGray
$lblHint.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
$lblHint.Text      = 'The EC keeps a ~5 % float range (80 = ~75-80 %). The applied value is remembered and - if checked above - re-applied after every logon.'
$form.Controls.Add($lblHint)

# ---- Autostart task ----
function Get-AutoTask {
    try { Get-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch { $null }
}

$script:suppressChk = $false
function Sync-AutoCheckbox {
    $t = Get-AutoTask
    $script:suppressChk = $true
    if ($null -eq $t) {
        $chkAuto.Checked = $false
        $chkAuto.Enabled = $false
        $chkAuto.Text    = 'Autostart task is not installed'
    } else {
        $chkAuto.Enabled = $true
        $chkAuto.Checked = ($t.State -ne 'Disabled')
        $chkAuto.Text    = 'Re-apply automatically at every logon'
    }
    $script:suppressChk = $false
}

$chkAuto.Add_CheckedChanged({
    if ($script:suppressChk) { return }
    try {
        if ($chkAuto.Checked) {
            Enable-ScheduledTask  -TaskName $taskName -ErrorAction Stop | Out-Null
        } else {
            Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not toggle the task:`n$_", 'Error', 'OK', 'Error') | Out-Null
        Sync-AutoCheckbox
    }
})

function Update-Ui {
    $s = Get-Status
    if ($null -eq $s.Limit) {
        $lblStatus.Text  = 'Could not read status'
        $lblDetail.Text  = 'framework_tool.exe returned nothing usable.'
        $lblCharge.Text  = ''
        $lblCharge2.Text = ''
        return
    }
    $script:barSoc   = if ($null -ne $s.Soc) { $s.Soc } else { 0 }
    $script:barLimit = $s.Limit
    $lblStatus.Text  = "Charge limit: $($s.Limit) %   -   Battery: $($s.Soc) %"
    $acTxt = if ($s.Ac -eq 'connected') { 'AC connected' } else { 'On battery' }
    $lblDetail.Text  = "$acTxt - battery $($s.State)"

    # Line 1: charge current / voltage / resulting power
    if ($null -ne $s.Ma) {
        $volt  = if ($null -ne $s.Mv) { '{0,6:N2} V' -f ($s.Mv / 1000.0) } else { '     - V' }
        $watt  = if ($null -ne $s.Mv) { '{0,5:N1} W' -f (($s.Mv / 1000.0) * ($s.Ma / 1000.0)) } else { '    - W' }
        $lblCharge.Text = 'Charge current {0,5} mA  @{1}  = {2}' -f $s.Ma, $volt, $watt
        $lblCharge.ForeColor = if ($s.Ma -gt 0) {
            [System.Drawing.Color]::FromArgb(40, 130, 60)
        } else {
            [System.Drawing.Color]::FromArgb(60, 60, 60)
        }
    } else {
        $lblCharge.Text = 'Charge current: not readable'
    }

    # Line 2: charger input limit plus battery health
    $parts = @()
    if ($null -ne $s.InMa) { $parts += ('Input limit {0} mA' -f $s.InMa) }
    if ($null -ne $s.Lfcc) { $parts += ('LFCC {0} mAh' -f $s.Lfcc) }
    $lblCharge2.Text = $parts -join '   '

    $track.Value = [Math]::Max($track.Minimum, [Math]::Min($track.Maximum, $s.Limit))
    $bar.Invalidate()
}

$btnRefresh.Add_Click({ Update-Ui })
$btnApply.Add_Click({
    $v = $track.Value
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $btnApply.Enabled = $false
    $res = Invoke-FwTool @('--charge-limit', "$v")
    $btnApply.Enabled = $true
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    if ($res -match 'ERROR') {
        [System.Windows.Forms.MessageBox]::Show($res, 'Error', 'OK', 'Error') | Out-Null
    } else {
        # Remember the value so the autostart task can restore it after a reboot
        try { Set-Content -Path $store -Value "$v" -Encoding ascii -NoNewline } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Limit applied, but $store is not writable:`n$_", 'Note', 'OK', 'Warning') | Out-Null
        }
    }
    Update-Ui
})

# Live refresh so the charge current can be watched
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Update-Ui })
$form.Add_FormClosing({ $timer.Stop(); $timer.Dispose() })

$form.Add_Shown({ $form.Activate(); Sync-AutoCheckbox; Update-Ui; $timer.Start() })
[void]$form.ShowDialog()
