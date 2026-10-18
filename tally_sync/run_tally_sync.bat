@echo off
cd /d "C:\Users\DELL\Documents\Sanyam\tally_sync"
echo ========== %date% %time% ========== >> tally_sync_log.txt
python tally_sync.py >> tally_sync_log.txt 2>&1
