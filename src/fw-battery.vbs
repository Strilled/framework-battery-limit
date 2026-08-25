' Desktop shortcut -> launches the GUI through the scheduled task
' "FrameworkBatteryLimit-GUI" (RunLevel Highest), so no UAC dialog appears.
CreateObject("WScript.Shell").Run "schtasks.exe /run /tn ""FrameworkBatteryLimit-GUI""", 0, False
