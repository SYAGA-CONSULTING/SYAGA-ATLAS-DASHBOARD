# Installation directe ATLAS v5.1 avec Auto-Update
Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "  ATLAS v5.1 - AUTO-UPDATE" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

# Télécharger et installer directement v5.1
$atlasPath = "C:\SYAGA-ATLAS"
New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null

# Sauvegarder config
@{
    Hostname = $env:COMPUTERNAME
    ClientName = "SYAGA"
    ServerType = "Physical"
    InstallDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Version = "5.1"
} | ConvertTo-Json | Out-File "$atlasPath\config.json" -Encoding UTF8

Write-Host "[INFO] Téléchargement agent v5.1..." -ForegroundColor Yellow
$agent = Invoke-RestMethod -Uri "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v5.1.ps1"
$agent | Out-File "$atlasPath\agent.ps1" -Encoding UTF8

Write-Host "[OK] Agent v5.1 installé" -ForegroundColor Green

# Créer tâche
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$atlasPath\agent.ps1`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask "SYAGA-ATLAS-Agent" -Action $action -Trigger $trigger -Principal $principal | Out-Null

Write-Host "[OK] Tâche planifiée créée" -ForegroundColor Green

# Test
& PowerShell.exe -ExecutionPolicy Bypass -File "$atlasPath\agent.ps1"

Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host "  INSTALLATION RÉUSSIE !" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "✅ Agent v5.1 avec AUTO-UPDATE actif" -ForegroundColor Yellow
Write-Host "✅ Vérifiera les updates chaque minute" -ForegroundColor Yellow
Write-Host "✅ Prêt pour v5.2, v5.3, etc..." -ForegroundColor Yellow