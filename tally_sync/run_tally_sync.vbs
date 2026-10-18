Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "cmd /c cd /d ""C:\Users\DELL\Documents\Sanyam\tally_sync"" && echo ========== %date% %time% ========== >> tally_sync_log.txt && python tally_sync.py >> tally_sync_log.txt 2>&1", 0, True
