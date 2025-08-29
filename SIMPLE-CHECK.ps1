# CHECK ULTRA SIMPLE SANS ERREURS

Write-Host "=== CHECK SIMPLE ===" -ForegroundColor Green

# 1. Redemarrer agent
Write-Host "Redemarrage agent..." -ForegroundColor Yellow
Stop-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2  
Start-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
Write-Host "OK" -ForegroundColor Green

Start-Sleep -Seconds 5

# 2. Logs
Write-Host ""
Write-Host "Derniers logs:" -ForegroundColor Yellow
$logFile = "C:\ATLAS\Logs\Agent-$(Get-Date -Format 'yyyyMMdd').log"
Get-Content $logFile -Tail 5 | ForEach-Object {
    if ($_ -match "400") {
        Write-Host $_ -ForegroundColor Red
    } elseif ($_ -match "SUCCES") {
        Write-Host $_ -ForegroundColor Green  
    } else {
        Write-Host $_ -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== FIN ===" -ForegroundColor Green