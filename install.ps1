<#
.SYNOPSIS
    Sets up the battery charge limit control for Framework laptops.

.DESCRIPTION
    Copies the scripts to the target directory, downloads framework_tool.exe from
    its GitHub release if needed, registers two scheduled tasks and creates
    shortcuts on the desktop and in the start menu.

    The two tasks:
      FrameworkBatteryLimit-GUI     on demand, RunLevel Highest -> GUI without a UAC dialog
      FrameworkBatteryLimit-Apply   at every logon -> re-applies the remembered limit

.PARAMETER InstallDir
    Target directory. Default: "%ProgramFiles%\FrameworkBatteryLimit".

.PARAMETER Limit
    Initial charge limit in percent. Default 80.
    Ignored if a limit.txt already exists.

.PARAMETER ToolVersion
    Release tag of FrameworkComputer/framework-system.

.PARAMETER SkipDownload
    Do not download framework_tool.exe (e.g. if you supplied it yourself).

.EXAMPLE
    .\install.ps1
    .\install.ps1 -InstallDir 'C:\Tools\fwbat' -Limit 70

.NOTES
    framework_tool.exe is made by Framework Computer Inc. and licensed under
    BSD-3-Clause. It is not bundled here but downloaded from the official
    GitHub release. See THIRD-PARTY-NOTICES.md.

.LINK
    https://github.com/FrameworkComputer/framework-system
#>
[CmdletBinding()]
param(
    [string] $InstallDir  = (Join-Path $env:ProgramFiles 'FrameworkBatteryLimit'),
    [ValidateRange(20, 100)]
    [int]    $Limit       = 80,
    [string] $ToolVersion = 'v0.6.5',
    [switch] $SkipDownload
)

$ErrorActionPreference = 'Stop'

# ---------- Preconditions ----------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Please run from an elevated PowerShell.'
}

$vendor = (Get-CimInstance Win32_ComputerSystem).Manufacturer
if ($vendor -notmatch 'Framework') {
    Write-Warning "Vendor is '$vendor', not Framework. framework_tool.exe will probably not find anything."
}

$src = Join-Path $PSScriptRoot 'src'
if (-not (Test-Path $src)) { throw "src\ not found next to $PSCommandPath" }

# ---------- Files ----------
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -Path (Join-Path $src '*') -Destination $InstallDir -Force
Write-Host "Scripts copied to $InstallDir."

$exe = Join-Path $InstallDir 'framework_tool.exe'
if (-not (Test-Path $exe) -and -not $SkipDownload) {
    $url = "https://github.com/FrameworkComputer/framework-system/releases/download/$ToolVersion/framework_tool.exe"
    Write-Host "Downloading framework_tool.exe ($ToolVersion) ..."
    Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
    Unblock-File -Path $exe
}
if (-not (Test-Path $exe)) { throw "framework_tool.exe missing in $InstallDir" }

$store = Join-Path $InstallDir 'limit.txt'
if (-not (Test-Path $store)) {
    Set-Content -Path $store -Value "$Limit" -Encoding ascii -NoNewline
    Write-Host "Initial value $Limit % written to limit.txt."
}

# ---------- Scheduled tasks ----------
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$me      = "$env:USERDOMAIN\$env:USERNAME"

$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest

$guiSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

Register-ScheduledTask -TaskName 'FrameworkBatteryLimit-GUI' `
    -Action (New-ScheduledTaskAction -Execute $wscript -Argument ('"{0}\fw-gui-run.vbs"' -f $InstallDir)) `
    -Principal $principal -Settings $guiSettings `
    -Description 'Starts the battery charge limit GUI with admin rights (triggered by the desktop shortcut).' `
    -Force | Out-Null

$applySettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $me
$trigger.Delay = 'PT15S'

Register-ScheduledTask -TaskName 'FrameworkBatteryLimit-Apply' `
    -Action (New-ScheduledTaskAction -Execute $wscript -Argument ('"{0}\fw-apply.vbs"' -f $InstallDir)) `
    -Trigger $trigger -Principal $principal -Settings $applySettings `
    -Description 'Re-applies the charge limit last chosen in the GUI after logon.' `
    -Force | Out-Null

Write-Host 'Scheduled tasks registered.'

# ---------- Shortcuts ----------
$ws = New-Object -ComObject WScript.Shell
foreach ($dir in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
    $lnk = Join-Path $dir 'Battery Charge Limit.lnk'
    $s   = $ws.CreateShortcut($lnk)
    $s.TargetPath       = $wscript
    $s.Arguments        = '"{0}\fw-battery.vbs"' -f $InstallDir
    $s.WorkingDirectory = $InstallDir
    $s.IconLocation     = (Join-Path $env:SystemRoot 'System32\powercpl.dll') + ',0'
    $s.Description      = 'Set the Framework battery charge limit'
    $s.Save()
}
Write-Host 'Shortcuts created on the desktop and in the start menu.'

# ---------- Harden the directory ----------
# The tasks run scripts from $InstallDir with admin rights. If that directory sits
# somewhere a normal user can write to, any non-elevated process could swap the
# scripts and thereby gain admin rights. Below %ProgramFiles% / %SystemRoot% the
# default ACL already covers this, so we leave those alone.
$protected = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:SystemRoot) |
    Where-Object { $_ } |
    Where-Object { $InstallDir.TrimEnd('\').StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }

if ($protected) {
    Write-Host 'Target sits in a protected path - ACL left unchanged.'
} else {
    $acl = Get-Acl $InstallDir
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {   # SYSTEM, Administrators
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier($sid)),
            'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    }
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $me, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -Path $InstallDir -AclObject $acl

    # Without changing the owner the user could simply reset the ACL again.
    try {
        $own = Get-Acl $InstallDir
        $own.SetOwner((New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        Set-Acl -Path $InstallDir -AclObject $own
    } catch {
        Write-Warning "Could not change the owner: $_"
    }
    Write-Host 'ACL hardened: write access for administrators only.'
}

# ---------- Done ----------
Write-Host ''
Write-Host 'Done. Current state:' -ForegroundColor Green
& $exe --charge-limit
Get-ScheduledTask -TaskName 'FrameworkBatteryLimit-*' | Select-Object TaskName, State | Format-Table -AutoSize
Write-Host 'The "Battery Charge Limit" shortcut now opens the GUI without a UAC dialog.'
