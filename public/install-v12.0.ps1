# ATLAS v12.0 - Installation avec logs enrichis
Write-Host ""
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ATLAS v12.0 - LOGS ENRICHIS & CONTRÔLE TOTAL" -ForegroundColor White
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Demander installation ou vérification
param(
    [switch]$Check
)

# Créer le dossier
$atlasDir = "C:\SYAGA-ATLAS"
if (!(Test-Path $atlasDir)) {
    New-Item -ItemType Directory -Path $atlasDir -Force | Out-Null
    Write-Host "[OK] Dossier créé: $atlasDir" -ForegroundColor Green
} else {
    Write-Host "[OK] Dossier existe: $atlasDir" -ForegroundColor Green
}

if ($Check) {
    Write-Host ""
    Write-Host "=== VÉRIFICATION ===" -ForegroundColor Yellow
    
    # Vérifier les tâches
    $agentTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    $updaterTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
    
    if ($agentTask) {
        Write-Host "[OK] Tâche Agent: $($agentTask.State)" -ForegroundColor Green
        
        # Vérifier version
        if (Test-Path "C:\SYAGA-ATLAS\agent.ps1") {
            $agentContent = Get-Content "C:\SYAGA-ATLAS\agent.ps1" -Raw
            if ($agentContent -match 'Version\s*=\s*"([^"]+)"') {
                Write-Host "[INFO] Version Agent: v$($matches[1])" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "[X] Tâche Agent non trouvée" -ForegroundColor Red
    }
    
    if ($updaterTask) {
        Write-Host "[OK] Tâche Updater: $($updaterTask.State)" -ForegroundColor Green
        
        # Vérifier version
        if (Test-Path "C:\SYAGA-ATLAS\updater.ps1") {
            $updaterContent = Get-Content "C:\SYAGA-ATLAS\updater.ps1" -Raw
            if ($updaterContent -match 'Version\s*=\s*"([^"]+)"') {
                Write-Host "[INFO] Version Updater: v$($matches[1])" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "[X] Tâche Updater non trouvée" -ForegroundColor Red
    }
    
    # Vérifier logs
    if (Test-Path "C:\SYAGA-ATLAS\atlas_log.txt") {
        $lastLines = Get-Content "C:\SYAGA-ATLAS\atlas_log.txt" -Tail 5
        Write-Host ""
        Write-Host "=== DERNIERS LOGS ===" -ForegroundColor Yellow
        $lastLines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    }
    
    exit 0
}

Write-Host "[1/6] Téléchargement agent v12.0..." -ForegroundColor Yellow
$agentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v12.0.ps1"
$agentPath = "$atlasDir\agent.ps1"

try {
    # Arrêter les tâches si elles existent
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    # Backup si existe
    if (Test-Path $agentPath) {
        Copy-Item $agentPath "$atlasDir\agent_backup.ps1" -Force
        Write-Host "[OK] Backup créé" -ForegroundColor Green
    }
    
    # Télécharger agent
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing
    Write-Host "[OK] Agent v12.0 téléchargé" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Téléchargement agent: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[2/6] Téléchargement updater v12.0..." -ForegroundColor Yellow
$updaterUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v12.0.ps1"
$updaterPath = "$atlasDir\updater.ps1"

try {
    # Backup si existe
    if (Test-Path $updaterPath) {
        Copy-Item $updaterPath "$atlasDir\updater_backup.ps1" -Force
    }
    
    # Télécharger updater
    Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
    Write-Host "[OK] Updater v12.0 téléchargé" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Téléchargement updater: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[3/6] Suppression anciennes tâches..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "[OK] Anciennes tâches supprimées" -ForegroundColor Green

Write-Host "[4/6] Création tâche Agent..." -ForegroundColor Yellow
$actionAgent = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""

$triggerAgent = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 2)

$settingsAgent = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -DontStopOnIdleEnd

$principalAgent = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$taskAgent = New-ScheduledTask `
    -Action $actionAgent `
    -Trigger $triggerAgent `
    -Settings $settingsAgent `
    -Principal $principalAgent `
    -Description "ATLAS Agent v12.0 - Collecte métriques et logs enrichis"

Register-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -InputObject $taskAgent | Out-Null
Write-Host "[OK] Tâche Agent créée (toutes les 2 minutes)" -ForegroundColor Green

Write-Host "[5/6] Création tâche Updater..." -ForegroundColor Yellow
$actionUpdater = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$updaterPath`""

$triggerUpdater = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

$settingsUpdater = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -DontStopOnIdleEnd

$principalUpdater = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

$taskUpdater = New-ScheduledTask `
    -Action $actionUpdater `
    -Trigger $triggerUpdater `
    -Settings $settingsUpdater `
    -Principal $principalUpdater `
    -Description "ATLAS Updater v12.0 - Auto-update intelligent"

Register-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -InputObject $taskUpdater | Out-Null
Write-Host "[OK] Tâche Updater créée (toutes les minutes)" -ForegroundColor Green

Write-Host "[6/6] Démarrage des tâches..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent"
Start-ScheduledTask -TaskName "SYAGA-ATLAS-Updater"
Write-Host "[OK] Tâches démarrées" -ForegroundColor Green

# Test immédiat
Write-Host ""
Write-Host "=== TEST IMMÉDIAT ===" -ForegroundColor Cyan
& $agentPath
Write-Host ""

# Afficher les logs JSON
if (Test-Path "C:\SYAGA-ATLAS\atlas_log.json") {
    Write-Host "=== LOGS JSON ENRICHIS ===" -ForegroundColor Cyan
    $jsonLogs = Get-Content "C:\SYAGA-ATLAS\atlas_log.json" -Tail 3
    $jsonLogs | ForEach-Object {
        $log = $_ | ConvertFrom-Json
        Write-Host "$($log.Timestamp) [$($log.Level)] $($log.Component): $($log.Message)" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host " ✅ ATLAS v12.0 INSTALLÉ AVEC SUCCÈS" -ForegroundColor White
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "NOUVEAUTÉS v12.0:" -ForegroundColor Yellow
Write-Host "  • Buffer circulaire 1000 lignes" -ForegroundColor Cyan
Write-Host "  • Logs JSON structurés" -ForegroundColor Cyan
Write-Host "  • Compteurs par niveau (INFO/WARN/ERROR)" -ForegroundColor Cyan
Write-Host "  • Métriques détaillées (processes, services)" -ForegroundColor Cyan
Write-Host "  • Composants logiques pour traçabilité" -ForegroundColor Cyan
Write-Host ""
Write-Host "Fichiers:" -ForegroundColor Gray
Write-Host "  Agent    : C:\SYAGA-ATLAS\agent.ps1" -ForegroundColor Gray
Write-Host "  Updater  : C:\SYAGA-ATLAS\updater.ps1" -ForegroundColor Gray
Write-Host "  Logs     : C:\SYAGA-ATLAS\atlas_log.txt" -ForegroundColor Gray
Write-Host "  JSON     : C:\SYAGA-ATLAS\atlas_log.json" -ForegroundColor Gray
Write-Host ""
Write-Host "Commandes:" -ForegroundColor Gray
Write-Host "  Vérifier : .\install-v12.0.ps1 -Check" -ForegroundColor Gray
Write-Host ""