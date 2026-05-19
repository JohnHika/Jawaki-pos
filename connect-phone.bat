@echo off
echo ========================================
echo CONNECTING YOUR PHONE
echo ========================================
echo.
echo Please do the following on your phone:
echo.
echo 1. UNLOCK your phone screen
echo 2. Go to Settings > About Phone
echo 3. Tap "Build Number" 7 times to enable Developer Options
echo 4. Go back to Settings > System > Developer Options
echo 5. Enable "USB Debugging"
echo 6. Connect phone to computer via USB cable
echo 7. When prompted on phone, tap "Allow" for USB debugging
echo.
echo ========================================
echo.
echo Checking for devices...
echo.

C:\Android\platform-tools\adb.exe devices

echo.
echo If you see a device listed above with "device" next to it, you're connected!
echo If not, try a different USB cable or USB port.
echo.
pause
