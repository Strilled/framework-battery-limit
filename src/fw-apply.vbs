' Starts fw-apply.ps1 completely invisibly (task action for FrameworkBatteryLimit-Apply).
Dim fso, here, ps1
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = here & "\fw-apply.ps1"

CreateObject("WScript.Shell").Run _
    "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, False
