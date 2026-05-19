@echo off
chcp 65001 >nul
title 🔗 Levisa POS — Phone Connection Manager
echo ============================================================
echo        LEVISA ADVENTURES POS — CONNECT YOUR PHONE
echo ============================================================
echo.

:: Check ADB exists
if not exist "C:\Android\platform-tools\adb.exe" (
    echo [!!] ADB not found at C:\Android\platform-tools\adb.exe
    echo.
    echo Please install Android Platform Tools first.
    pause
    exit /b 1
)

:: Check Flutter exists
if not exist "C:\src\flutter\bin\flutter.bat" (
    echo [!] Flutter not found at C:\src\flutter\bin
    echo.
    echo Continuing with ADB only...
)

:menu
cls
echo ╔═══════════════════════════════════════════════════════════╗
echo ║     LEVISA ADVENTURES POS — PHONE CONNECTION HUB        ║
echo ╠═══════════════════════════════════════════════════════════╣
echo ║                                                         ║
echo ║  1  🔍  Scan for connected devices                      ║
echo ║  2  📦  Build and Install APK (Full)                   ║
echo ║  3  📱  Install APK only (skip build)                   ║
echo ║  4  🚀  Launch app on phone                             ║
echo ║  5  📋  View device info                                ║
echo ║  6  🔄  Restart ADB server                              ║
echo ║  7  ❌  Disconnect all devices                          ║
echo ║  8  📖  Show installation guide                         ║
echo ║  0  🚪  Exit                                            ║
echo ║                                                         ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.
set /p choice="Select option (0-8): "

if "%choice%"=="1" goto scan
if "%choice%"=="2" goto build_install
if "%choice%"=="3" goto install_only
if "%choice%"=="4" goto launch
if "%choice%"=="5" goto device_info
if "%choice%"=="6" goto restart_adb
if "%choice%"=="7" goto disconnect
if "%choice%"=="8" goto guide
if "%choice%"=="0" exit /b

echo Invalid option
timeout /t 2 >nul
goto menu

:scan
cls
echo ============================================================
echo  SCANNING FOR DEVICES...
echo ============================================================
echo.
echo Make sure your phone is:
echo  1. Unlocked
echo  2. USB Debugging enabled (Settings ^> Developer Options)
echo  3. Connected via USB cable
echo  4. "Allow USB debugging?" acknowledged on phone
echo.
C:\Android\platform-tools\adb.exe devices -l
echo.
echo ── Tips ─────────────────────────────────────────────────
echo  If no device shown:
echo   - Try a different USB cable
echo   - Try a different USB port (USB 2.0 recommended)
echo   - Check phone shows "USB debugging connected" in notification
echo   - Revoke auth: Settings ^> Developer Options ^> Revoke USB debugging
echo ──────────────────────────────────────────────────────────
echo.
pause
goto menu

:build_install
cls
echo ============================================================
echo  BUILDING AND INSTALLING APK...
echo ============================================================
echo.
:: Check device connected
C:\Android\platform-tools\adb.exe devices | findstr /R "device$" >nul
if errorlevel 1 (
    echo [!!] No device connected! Please connect your phone first.
    echo.
    pause
    goto menu
)

:: Set paths
set JAVA_HOME=C:\Program Files\Java\jdk-26.0.1
set PATH=C:\src\flutter\bin;%PATH%;%JAVA_HOME%\bin

cd /d C:\Projects\pos-system\mobile

echo [1/3] Cleaning previous build...
call flutter clean >nul 2>&1
echo       Done!

echo [2/3] Building APK (this takes 5-15 minutes)...
echo.
call flutter build apk --release
if errorlevel 1 (
    echo.
    echo [!!] BUILD FAILED!
    echo Check the errors above and fix them.
    echo.
    pause
    goto menu
)

echo.
echo [3/3] Installing on device...
C:\Android\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-release.apk
if errorlevel 1 (
    echo.
    echo [!!] Installation failed!
    echo.
    pause
    goto menu
)

echo.
echo ============================================================
echo  ✅  SUCCESS! APK built and installed!
echo ============================================================
echo.
echo Launching app...
C:\Android\platform-tools\adb.exe shell am start -n com.levisaadventures.pos/.MainActivity
echo.
echo App started on your phone!
echo.
pause
goto menu

:install_only
cls
echo ============================================================
echo  INSTALL APK ONLY
echo ============================================================
echo.
:: Check device connected
C:\Android\platform-tools\adb.exe devices | findstr /R "device$" >nul
if errorlevel 1 (
    echo [!!] No device connected!
    pause
    goto menu
)

:: Find APK
set APK_PATH=C:\Projects\pos-system\mobile\build\app\outputs\flutter-apk\app-release.apk
if not exist "%APK_PATH%" (
    set APK_PATH=C:\Users\Public\LevisaPOS_Latest.apk
)
if not exist "%APK_PATH%" (
    echo [!!] No APK found! Build it first (option 2).
    pause
    goto menu
)

echo Installing %APK_PATH%...
C:\Android\platform-tools\adb.exe install -r "%APK_PATH%"
if errorlevel 1 (
    echo.
    echo [!!] Installation failed!
    pause
    goto menu
)

echo.
echo ✅  APK installed successfully!
echo.
pause
goto menu

:launch
cls
echo ============================================================
echo  LAUNCH APP ON PHONE
echo ============================================================
echo.
C:\Android\platform-tools\adb.exe shell am start -n com.levisaadventures.pos/.MainActivity
if errorlevel 1 (
    echo [!!] Failed to launch app.
    echo Make sure the app is installed and device is connected.
    pause
    goto menu
)
echo ✅  App launched!
echo.
pause
goto menu

:device_info
cls
echo ============================================================
echo  DEVICE INFORMATION
echo ============================================================
echo.
for /f "tokens=*" %%a in ('C:\Android\platform-tools\adb.exe get-state 2^>nul') do set STATE=%%a
if "%STATE%"=="" (
    echo No device connected.
    echo.
    pause
    goto menu
)
echo State: %STATE%
echo.
echo Device model:
C:\Android\platform-tools\adb.exe shell getprop ro.product.model 2>nul
echo Android version:
C:\Android\platform-tools\adb.exe shell getprop ro.build.version.release 2>nul
echo SDK level:
C:\Android\platform-tools\adb.exe shell getprop ro.build.version.sdk 2>nul
echo Resolution:
C:\Android\platform-tools\adb.exe shell wm size 2>nul
echo Density:
C:\Android\platform-tools\adb.exe shell wm density 2>nul
echo.
pause
goto menu

:restart_adb
cls
echo ============================================================
echo  RESTARTING ADB SERVER...
echo ============================================================
echo.
C:\Android\platform-tools\adb.exe kill-server
echo ADB server stopped.
timeout /t 2 /nobreak >nul
C:\Android\platform-tools\adb.exe start-server
echo ADB server started.
echo.
pause
goto menu

:disconnect
cls
echo ============================================================
echo  DISCONNECTING ALL DEVICES
echo ============================================================
echo.
C:\Android\platform-tools\adb.exe disconnect
echo All devices disconnected.
echo.
pause
goto menu

:guide
cls
echo ╔═══════════════════════════════════════════════════════════╗
echo ║           HOW TO CONNECT YOUR PHONE                      ║
echo ╠═══════════════════════════════════════════════════════════╣
echo ║                                                         ║
echo ║  STEP 1: Enable Developer Options                       ║
echo ║   Settings ^> About Phone ^> Tap "Build Number" 7 times  ║
echo ║                                                         ║
echo ║  STEP 2: Enable USB Debugging                           ║
echo ║   Settings ^> Developer Options ^> USB Debugging: ON     ║
echo ║                                                         ║
echo ║  STEP 3: Connect via USB                                ║
echo ║   Use a data cable. On phone select "File Transfer"      ║
echo ║                                                         ║
echo ║  STEP 4: Accept prompt on phone                         ║
echo ║   Tap "Allow USB debugging?" when prompted              ║
echo ║                                                         ║
echo ║  STEP 5: Select option 1 to verify connection           ║
echo ║                                                         ║
echo ║  TROUBLESHOOTING:                                       ║
echo ║   - Try different USB cable                              ║
echo ║   - Try USB 2.0 port (not USB 3.0)                      ║
echo ║   - Revoke USB auth: Dev Options ^> Revoke auth          ║
echo ║   - Restart ADB: Option 6                                ║
echo ║   - Restart phone and computer                           ║
echo ║                                                         ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.
pause
goto menu
