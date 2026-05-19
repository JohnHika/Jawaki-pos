@echo off
echo ========================================
echo LEVISA POS - CRASH LOG READER
echo ========================================
echo.
echo Please install the APK on your phone, then:
echo 1. Open the app
echo 2. Wait for it to crash
echo 3. Come back here - logs will be captured
echo.
echo Press Ctrl+C to stop...
echo ========================================
echo.

adb logcat -c
adb logcat | findstr /C:"Flutter" /C:"POS" /C:"AuthService" /C:"StorageService" /C:"Database" /C:"Error" /C:"Exception" /C:"AndroidRuntime"
