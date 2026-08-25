<#
.SYNOPSIS
    Removes the tasks, the shortcuts and (optionally) the install directory.

.PARAMETER InstallDir
    Install directory to remove.

.PARAMETER KeepFiles
    Leave the directory in place, only remove tasks and shortcuts.

.PARAMETER ResetLimit
    Set the charge limit back to 100 % before removing anything.

.PARAMETER LegacyTaskNames
    Also remove the tasks and shortcut of the older German naming
    (FrameworkAkku-GUI / FrameworkAkku-Apply / "Akku-Ladelimit").
#>
[CmdletBinding()]
param(
    [string] $InstallDir = (Join-Path $env:ProgramFiles 'FrameworkBatteryLimit'),
    [switch] $KeepFiles,
    [switch] $ResetLimit,
    [switch] $LegacyTaskNames
)

$ErrorActionPreference = 'Stop'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Please run from an elevated PowerShell.'
}

if ($ResetLimit) {
    $exe = Join-Path $InstallDir 'framework_tool.exe'
    if (Test-Path $exe) {
        & $exe --charge-limit 100
        Write-Host 'Charge limit reset to 100 %.'
    } else {
        Write-Warning 'framework_tool.exe not found - limit unchanged. It stays active until the next reboot.'
    }
}

$tasks     = @('FrameworkBatteryLimit-GUI', 'FrameworkBatteryLimit-Apply')
$shortcuts = @('Battery Charge Limit.lnk')
if ($LegacyTaskNames) {
    $tasks     += @('FrameworkAkku-GUI', 'FrameworkAkku-Apply')
    $shortcuts += 'Akku-Ladelimit.lnk'
}

foreach ($t in $tasks) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $t -Confirm:$false
        Write-Host "Task removed: $t"
    }
}

foreach ($dir in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
    foreach ($name in $shortcuts) {
        $lnk = Join-Path $dir $name
        if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host "Shortcut removed: $lnk" }
    }
}

if (-not $KeepFiles -and (Test-Path $InstallDir)) {
    # The hardening can block deletion - restore inheritance first.
    try {
        $acl = Get-Acl $InstallDir
        $acl.SetAccessRuleProtection($false, $true)
        Set-Acl -Path $InstallDir -AclObject $acl
    } catch { }
    Remove-Item $InstallDir -Recurse -Force
    Write-Host "Directory removed: $InstallDir"
}

Write-Host 'Uninstall complete.'
Write-Host 'Note: a charge limit set in the BIOS is unaffected by this.'
