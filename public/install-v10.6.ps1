# ATLAS v10.6 - INSTALLATION 2 TÂCHES SÉPARÉES
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ATLAS v10.6 - INSTALLATION" -ForegroundColor Cyan
Write-Host "  2 TÂCHES SÉPARÉES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$atlasPath = "C:\SYAGA-ATLAS"
$agentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v10.6.ps1"
$updaterUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v10.6.ps1"

# Créer dossier
Write-Host "[1/5] Creation dossier..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null

# Télécharger agent
Write-Host "[2/5] Telechargement agent v10.6..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $agentUrl -OutFile "$atlasPath\agent.ps1" -UseBasicParsing
    Write-Host "  [OK] Agent telecharge" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] $_ " -ForegroundColor Red
    exit 1
}

# Télécharger updater
Write-Host "[3/5] Telechargement updater v10.6..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $updaterUrl -OutFile "$atlasPath\updater.ps1" -UseBasicParsing
    Write-Host "  [OK] Updater telecharge" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] $_ " -ForegroundColor Red
    exit 1
}

# Supprimer anciennes tâches
Write-Host "[4/5] Suppression anciennes taches..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -EA SilentlyContinue

# Créer les 2 tâches
Write-Host "[5/5] Creation 2 taches planifiees..." -ForegroundColor Yellow

# TÂCHE 1: Agent (toutes les minutes)
$agentAction = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$atlasPath\agent.ps1`""

$agentTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$agentSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 1) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries

Register-ScheduledTask "SYAGA-ATLAS-Agent" `
    -Action $agentAction `
    -Trigger $agentTrigger `
    -Principal $principal `
    -Settings $agentSettings | Out-Null

Write-Host "  [OK] Tache Agent creee (1 min)" -ForegroundColor Green

# TÂCHE 2: Updater (toutes les minutes aussi pour debug)
$updaterAction = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$atlasPath\updater.ps1`""

$updaterTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30) `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

$updaterSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries

Register-ScheduledTask "SYAGA-ATLAS-Updater" `
    -Action $updaterAction `
    -Trigger $updaterTrigger `
    -Principal $principal `
    -Settings $updaterSettings | Out-Null

Write-Host "  [OK] Tache Updater creee (1 min)" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  INSTALLATION REUSSIE !" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Architecture v10.0 installee:" -ForegroundColor Yellow
Write-Host "  • SYAGA-ATLAS-Agent   : Metriques/logs (1 min)" -ForegroundColor White
Write-Host "  • SYAGA-ATLAS-Updater : Updates (1 min)" -ForegroundColor White
Write-Host ""
Write-Host "Avantages:" -ForegroundColor Cyan
Write-Host "  • 2 taches separees = pas de blocage" -ForegroundColor White
Write-Host "  • Timeout automatique = pas de freeze" -ForegroundColor White
Write-Host "  • Restart automatique = resilient" -ForegroundColor White
Write-Host ""

# Test immédiat
Write-Host "Test immediat agent..." -ForegroundColor Yellow
& PowerShell.exe -ExecutionPolicy Bypass -File "$atlasPath\agent.ps1"

Write-Host ""
Write-Host "Test immediat updater..." -ForegroundColor Yellow
& PowerShell.exe -ExecutionPolicy Bypass -File "$atlasPath\updater.ps1"