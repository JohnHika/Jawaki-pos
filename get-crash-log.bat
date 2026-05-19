@echo off
echo ========================================
echo LEVISA POS - CRASH LOG CAPTURE
echo ========================================
echo.
echo INSTRUCTIONS:
echo 1. Make sure your phone is connected via USB
echo 2. Install the debug APK first
echo 3. Open the app on your phone
echo 4. Wait for it to crash
echo 5. Come back here - logs will appear below
echo.
echo Press Ctrl+C to stop logging
echo ========================================
echo.
echo Clearing old logs...
adb logcat -c
echo.
echo Starting crash capture (waiting for app to crash)...
echo.
adb logcat -s AndroidRuntime:* Flutter:* POS:* AuthService:* StorageService:* Database:* SQLite:* getit:* Exception:* Error:* ActivityManager:*
