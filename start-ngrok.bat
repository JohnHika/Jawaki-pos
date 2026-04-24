@echo off
echo Starting ngrok tunnel...
echo.
echo Please wait while ngrok starts...
echo.
echo Once started, your app will be available at the URL shown in the ngrok window.
echo Press Ctrl+C to stop the tunnel.
echo.
ngrok http 3000
