@echo off
echo ========================================
echo   Building Levisa Adventures POS APK
echo ========================================
echo.

echo Setting JAVA_HOME and Flutter paths...
set JAVA_HOME=C:\Program Files\Java\jdk-26.0.1
set PATH=C:\src\flutter\bin;%PATH%;%JAVA_HOME%\bin

echo Changing to mobile directory...
cd /d C:\Projects\pos-system\mobile

echo.
echo Starting Flutter build...
echo This will take 10-15 minutes...
echo.

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
