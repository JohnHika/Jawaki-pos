@echo off
setlocal enabledelayedexpansion

echo ========================================
echo LEVISA POS - AUTO BUILD & INSTALL
echo ========================================
echo.

REM Set JAVA_HOME
set JAVA_HOME=C:\Program Files\Java\jdk-26.0.1
set PATH=%JAVA_HOME%\bin;%PATH%

REM Navigate to mobile directory
cd /d C:\Projects\pos-system\mobile

echo [1/4] Building APK...
echo.

REM Build the APK
call C:\src\flutter\bin\flutter build apk --release 2>&1 | findstr /C:"Built" /C:"error" /C:"Failed"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Build failed!
    echo.
    pause
    exit /b 1
)

echo.
echo [2/4] Build successful!
echo.

REM Check if device is connected
echo [3/4] Checking device connection...
C:\Android\platform-tools\adb.exe devices | findstr "device" >nul

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] No device connected or unauthorized!
    echo Please connect your phone and authorize USB debugging.
    echo.
    pause
    exit /b 1
)

echo Device found!
echo.

REM Install APK
echo [4/4] Installing APK on device...
C:\Android\platform-tools\adb.exe install -r C:\Projects\pos-system\mobile\build\app\outputs\flutter-apk\app-release.apk

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Installation failed!
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================
echo [SUCCESS] APK installed successfully!
echo ========================================
echo.
echo The app is now updated on your phone.
echo You can open it and test the new features.
echo.

REM Optionally launch the app
echo Launching app...
C:\Android\platform-tools\adb.exe shell am start -n com.levisaadventures.pos/com.levisaadventures.pos.MainActivity

echo.
echo Done! You can now test the app.
echo.
pause
