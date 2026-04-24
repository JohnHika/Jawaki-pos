@echo off
echo ========================================
echo   Levisa Adventures POS - Startup
echo ========================================
echo.

echo [1/3] Starting Backend Server...
cd backend
start "Backend" cmd /k "npm run start:dev"
timeout /t 5 /nobreak >nul

echo [2/3] Starting Frontend Server...
cd ..\store-management-system
start "Frontend" cmd /k "npm run dev"
timeout /t 5 /nobreak >nul

echo [3/3] Starting LocalTunnel...
start "Tunnel" cmd /k "lt --port 3000"
timeout /t 10 /nobreak >nul

echo.
echo ========================================
echo   Servers Started!
echo ========================================
echo.
echo Backend:  http://localhost:3000
echo Frontend: http://localhost:3001
echo.
echo Check the 'Tunnel' window for your public URL
echo.
echo QR Code:  file:///%CD%\store-management-system\public\qr-code-latest.png
echo.
echo Press any key to exit...
pause >nul
