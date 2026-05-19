@echo off
echo ========================================
echo   Cleaning & Rebuilding Levisa Adventures POS
echo ========================================
echo.

echo Setting JAVA_HOME and Flutter paths...
set JAVA_HOME=C:\Program Files\Java\jdk-26.0.1
set PATH=C:\src\flutter\bin;%PATH%;%JAVA_HOME%\bin

echo.
echo Cleaning old build...
cd /d C:\Projects\pos-system\mobile
flutter clean

echo.
echo Getting fresh dependencies...
flutter pub get

echo.
echo Building release APK...
flutter build apk --release

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo   BUILD SUCCESSFUL!
    echo ========================================
    echo.
    echo APK location:
    echo C:\Projects\pos-system\mobile\build\app\outputs\flutter-apk\app-release.apk
    echo.
) else (
    echo.
    echo ========================================
    echo   BUILD FAILED
    echo ========================================
    echo.
)

pause
