# ATLAS INSTALLER v10.3 - VERSION FONDATION
# Installe l'agent v10.3 et l'updater v10.0

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  ATLAS v10.3 - Installation FONDATION" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# Créer structure
$atlasPath = "C:\SYAGA-ATLAS"
New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null

# URLs
$agentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v10.3.ps1"
$updaterUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v10.0.ps1"

# 1. TÉLÉCHARGER AGENT v10.3
Write-Host "[1/4] Telechargement agent v10.3..." -ForegroundColor Yellow
try {
    $agent = Invoke-RestMethod -Uri $agentUrl -UseBasicParsing
    $agent | Out-File "$atlasPath\agent.ps1" -Encoding UTF8 -Force
    Write-Host "  ✓ Agent v10.3 telecharge" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Erreur telechargement agent: $_" -ForegroundColor Red
    exit 1
}

# 2. TÉLÉCHARGER UPDATER v10.0
Write-Host "[2/4] Telechargement updater v10.0..." -ForegroundColor Yellow
try {
    $updater = Invoke-RestMethod -Uri $updaterUrl -UseBasicParsing
    $updater | Out-File "$atlasPath\updater.ps1" -Encoding UTF8 -Force
    Write-Host "  ✓ Updater v10.0 telecharge" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Erreur telechargement updater: $_" -ForegroundColor Red
    exit 1
}

# 3. CRÉER TÂCHE AGENT
Write-Host "[3/4] Creation tache SYAGA-ATLAS-Agent..." -ForegroundColor Yellow

# Supprimer ancienne tâche si existe
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue

# Script pour la tâche agent (exécution unique)
$agentScript = @'
$logFile = "C:\SYAGA-ATLAS\agent_task.log"

# Log début
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Tache Agent demarree" | Out-File $logFile -Append

# Exécuter l'agent
try {
    & PowerShell.exe -ExecutionPolicy Bypass -File "C:\SYAGA-ATLAS\agent.ps1"
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Agent execute avec succes" | Out-File $logFile -Append
} catch {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Erreur agent: $_" | Out-File $logFile -Append
}

# Log fin
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Tache Agent terminee" | Out-File $logFile -Append
'@

$agentScript | Out-File "$atlasPath\agent-task.ps1" -Encoding UTF8 -Force

# Créer tâche agent (toutes les 2 minutes)
$agentAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$atlasPath\agent-task.ps1`""
$agentTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration ([TimeSpan]::MaxValue)
$agentSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$agentPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Action $agentAction -Trigger $agentTrigger -Settings $agentSettings -Principal $agentPrincipal -Force | Out-Null
Write-Host "  ✓ Tache Agent creee (execution toutes les 2 minutes)" -ForegroundColor Green

# 4. CRÉER TÂCHE UPDATER
Write-Host "[4/4] Creation tache SYAGA-ATLAS-Updater..." -ForegroundColor Yellow

# Supprimer ancienne tâche si existe
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -EA SilentlyContinue

# Script pour la tâche updater (exécution unique)
$updaterScript = @'
$logFile = "C:\SYAGA-ATLAS\updater_task.log"

# Log début
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Tache Updater demarree" | Out-File $logFile -Append

# Exécuter l'updater
try {
    & PowerShell.exe -ExecutionPolicy Bypass -File "C:\SYAGA-ATLAS\updater.ps1"
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Updater execute avec succes" | Out-File $logFile -Append
} catch {
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Erreur updater: $_" | Out-File $logFile -Append
}

# Log fin
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Tache Updater terminee" | Out-File $logFile -Append
'@

$updaterScript | Out-File "$atlasPath\updater-task.ps1" -Encoding UTF8 -Force

# Créer tâche updater (toutes les 2 minutes, décalée de 30 secondes)
$updaterAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$atlasPath\updater-task.ps1`""
$updaterTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(90) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration ([TimeSpan]::MaxValue)
$updaterSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$updaterPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Action $updaterAction -Trigger $updaterTrigger -Settings $updaterSettings -Principal $updaterPrincipal -Force | Out-Null
Write-Host "  ✓ Tache Updater creee (verification toutes les 2 minutes)" -ForegroundColor Green

# DÉMARRER LES TÂCHES
Write-Host ""
Write-Host "Demarrage des taches..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -EA SilentlyContinue
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -EA SilentlyContinue

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "  INSTALLATION v10.3 TERMINEE !" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Agent    : v10.3 FONDATION" -ForegroundColor Cyan
Write-Host "Updater  : v10.0" -ForegroundColor Cyan
Write-Host "Taches   : 2 (Agent + Updater)" -ForegroundColor Cyan
Write-Host "Frequence: Toutes les 2 minutes" -ForegroundColor Cyan
Write-Host ""