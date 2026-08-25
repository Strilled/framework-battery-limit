' Task action for "FrameworkBatteryLimit-GUI": starts the GUI without a console window.
' Do not call directly - that is what fw-battery.vbs is for (it triggers the task).
Dim fso, here, ps1
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = here & "\fw-battery.ps1"

CreateObject("WScript.Shell").Run _
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, True
