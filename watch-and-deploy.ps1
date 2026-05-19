# Watch for Flutter/Dart file changes and auto-build
$watchPath = "C:\Projects\pos-system\mobile\lib"
$buildScript = "C:\Projects\pos-system\auto-build-install.bat"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "LEVISA POS - AUTO DEPLOY WATCHER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Watching for changes in: $watchPath" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

$lastBuildTime = Get-Date
$debounceSeconds = 5
$lastChangeTime = Get-Date

# Create file system watcher
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $watchPath
$watcher.Filter = "*.dart"
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

$onChange = {
    $global:lastChangeTime = Get-Date
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Change detected..." -ForegroundColor Gray

    # Wait for debounce period
    Start-Sleep -Seconds $using:debounceSeconds

    if ((New-TimeSpan -Start $global:lastChangeTime -End (Get-Date)).TotalSeconds -ge $using:debounceSeconds) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Building and installing..." -ForegroundColor Green

        # Run build script
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $using:buildScript -WindowStyle Normal -Wait

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Deploy complete! Ready for testing." -ForegroundColor Green
        Write-Host ""
    }
}

Register-ObjectEvent $watcher "Created" -Action $onChange
Register-ObjectEvent $watcher "Changed" -Action $onChange
Register-ObjectEvent $watcher "Renamed" -Action $onChange

Write-Host "Watcher started. Waiting for file changes..." -ForegroundColor Cyan
Write-Host ""

# Keep script running
while ($true) {
    Start-Sleep -Milliseconds 500
}
