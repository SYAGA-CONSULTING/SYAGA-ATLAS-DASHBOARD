# ════════════════════════════════════════════════════
# ATLAS v13.0 - INSTALLATION COMPLÈTE
# ════════════════════════════════════════════════════

param(
    [switch]$Check,
    [switch]$Uninstall
)

$VERSION = "13.0"
$BASE_URL = "https://white-river-053fc6703.2.azurestaticapps.net/public"

Write-Host ""
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ATLAS v$VERSION - ARCHITECTURE PROFESSIONNELLE" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Désinstallation
if ($Uninstall) {
    Write-Host "[DESINSTALLATION] Suppression ATLAS..." -ForegroundColor Yellow
    
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
    
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -ErrorAction SilentlyContinue
    
    Remove-Item -Path "C:\SYAGA-ATLAS" -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host "[OK] ATLAS désinstallé" -ForegroundColor Green
    exit 0
}

# Vérification seulement
if ($Check) {
    Write-Host "[CHECK] Vérification installation..." -ForegroundColor Yellow
    
    $agentPath = "C:\SYAGA-ATLAS\agent.ps1"
    $updaterPath = "C:\SYAGA-ATLAS\updater.ps1"
    
    # Vérifier les fichiers
    if (Test-Path $agentPath) {
        $agentContent = Get-Content $agentPath -First 5 | Out-String
        if ($agentContent -match 'Version\s*=\s*"([^"]+)"') {
            Write-Host "[OK] Agent v$($matches[1]) installé" -ForegroundColor Green
        }
    } else {
        Write-Host "[X] Agent non trouvé" -ForegroundColor Red
    }
    
    if (Test-Path $updaterPath) {
        $updaterContent = Get-Content $updaterPath -First 5 | Out-String
        if ($updaterContent -match 'Version\s*=\s*"([^"]+)"') {
            Write-Host "[OK] Updater v$($matches[1]) installé" -ForegroundColor Green
        }
    } else {
        Write-Host "[X] Updater non trouvé" -ForegroundColor Red
    }
    
    # Vérifier l'état de l'updater
    $statePath = "C:\SYAGA-ATLAS\updater-state.json"
    if (Test-Path $statePath) {
        try {
            $state = Get-Content $statePath -Raw | ConvertFrom-Json
            Write-Host "[OK] État updater : $($state.Status)" -ForegroundColor Green
            Write-Host "  Version actuelle : $($state.CurrentVersion)" -ForegroundColor White
            Write-Host "  Dernière vérification : $($state.LastCheck)" -ForegroundColor White
        } catch {
            Write-Host "[X] État updater illisible" -ForegroundColor Red
        }
    } else {
        Write-Host "[X] État updater non trouvé" -ForegroundColor Red
    }
    
    # Vérifier les tâches
    $agentTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    $updaterTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
    
    if ($agentTask) {
        Write-Host "[OK] Tâche Agent : $($agentTask.State)" -ForegroundColor Green
    } else {
        Write-Host "[X] Tâche Agent non trouvée" -ForegroundColor Red
    }
    
    if ($updaterTask) {
        Write-Host "[OK] Tâche Updater : $($updaterTask.State)" -ForegroundColor Green
    } else {
        Write-Host "[X] Tâche Updater non trouvée" -ForegroundColor Red
    }
    
    exit 0
}

# INSTALLATION PRINCIPALE
$atlasPath = "C:\SYAGA-ATLAS"
$logsPath = "$atlasPath\logs"

# Créer les dossiers
if (!(Test-Path $atlasPath)) {
    New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null
    Write-Host "[OK] Dossier créé : $atlasPath" -ForegroundColor Green
} else {
    Write-Host "[OK] Dossier existe : $atlasPath" -ForegroundColor Green
}

if (!(Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    Write-Host "[OK] Dossier logs créé : $logsPath" -ForegroundColor Green
}

# 1. TÉLÉCHARGER AGENT v13.0
Write-Host "[1/6] Téléchargement agent v$VERSION..." -ForegroundColor Yellow

$agentUrl = "$BASE_URL/agent-v$VERSION.ps1"
$agentPath = "$atlasPath\agent.ps1"

# Backup si existe
if (Test-Path $agentPath) {
    $backupPath = "$atlasPath\agent_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    Copy-Item $agentPath $backupPath -Force
    Write-Host "[OK] Backup créé" -ForegroundColor Green
}

try {
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing
    Write-Host "[OK] Agent v$VERSION téléchargé" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Téléchargement agent : $_" -ForegroundColor Red
    exit 1
}

# 2. TÉLÉCHARGER UPDATER v13.0
Write-Host "[2/6] Téléchargement updater v$VERSION..." -ForegroundColor Yellow

$updaterUrl = "$BASE_URL/updater-v$VERSION.ps1"
$updaterPath = "$atlasPath\updater.ps1"

# Backup si existe
if (Test-Path $updaterPath) {
    $backupPath = "$atlasPath\updater_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    Copy-Item $updaterPath $backupPath -Force
    Write-Host "[OK] Backup updater créé" -ForegroundColor Green
}

try {
    Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
    Write-Host "[OK] Updater v$VERSION téléchargé" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Téléchargement updater : $_" -ForegroundColor Red
    exit 1
}

# 3. SUPPRIMER ANCIENNES TÂCHES
Write-Host "[3/6] Suppression anciennes tâches..." -ForegroundColor Yellow

Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue

Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "[OK] Anciennes tâches supprimées" -ForegroundColor Green

# 4. CRÉER TÂCHE AGENT
Write-Host "[4/6] Création tâche Agent..." -ForegroundColor Yellow

$agentAction = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentPath`""

$agentTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10) `
    -RepetitionInterval (New-TimeSpan -Minutes 2) `
    -RepetitionDuration ([System.TimeSpan]::MaxValue)

$agentSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -DontStopOnIdleEnd

$agentPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" `
    -Action $agentAction `
    -Trigger $agentTrigger `
    -Settings $agentSettings `
    -Principal $agentPrincipal `
    -Force | Out-Null

Write-Host "[OK] Tâche Agent créée (toutes les 2 minutes)" -ForegroundColor Green

# 5. CRÉER TÂCHE UPDATER
Write-Host "[5/6] Création tâche Updater..." -ForegroundColor Yellow

$updaterAction = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$updaterPath`""

$updaterTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration ([System.TimeSpan]::MaxValue)

$updaterSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -DontStopOnIdleEnd

$updaterPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" `
    -Action $updaterAction `
    -Trigger $updaterTrigger `
    -Settings $updaterSettings `
    -Principal $updaterPrincipal `
    -Force | Out-Null

Write-Host "[OK] Tâche Updater créée (toutes les minutes)" -ForegroundColor Green

# 6. DÉMARRER LES TÂCHES
Write-Host "[6/6] Démarrage des tâches..." -ForegroundColor Yellow

Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent"
Start-ScheduledTask -TaskName "SYAGA-ATLAS-Updater"

Write-Host "[OK] Tâches démarrées" -ForegroundColor Green

# TEST IMMÉDIAT AGENT
Write-Host ""
Write-Host "=== TEST AGENT v$VERSION ===" -ForegroundColor Cyan

& $agentPath

# INITIALISATION UPDATER
Write-Host ""
Write-Host "=== INITIALISATION UPDATER v$VERSION ===" -ForegroundColor Cyan

& $updaterPath

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " ATLAS v$VERSION INSTALLÉ AVEC SUCCÈS" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "NOUVELLES FONCTIONNALITÉS v$VERSION :" -ForegroundColor Yellow
Write-Host "  - Mutex pour instance unique" -ForegroundColor White
Write-Host "  - Persistance d'état JSON" -ForegroundColor White
Write-Host "  - Validation avant mise à jour" -ForegroundColor White
Write-Host "  - Système de rollback" -ForegroundColor White
Write-Host "  - Logs avec rotation" -ForegroundColor White
Write-Host "  - Monitoring complet updater" -ForegroundColor White
Write-Host ""
Write-Host "Fichiers :" -ForegroundColor Yellow
Write-Host "  Agent    : $agentPath (v$VERSION)" -ForegroundColor White
Write-Host "  Updater  : $updaterPath (v$VERSION)" -ForegroundColor White
Write-Host "  État     : $atlasPath\updater-state.json" -ForegroundColor White
Write-Host "  Logs     : $logsPath\" -ForegroundColor White
Write-Host ""
Write-Host "Commandes :" -ForegroundColor Yellow
Write-Host "  Vérifier : .\install-v$VERSION.ps1 -Check" -ForegroundColor White
Write-Host "  Désinstaller : .\install-v$VERSION.ps1 -Uninstall" -ForegroundColor White
Write-Host ""

# VÉRIFICATION FINALE
$tasks = Get-ScheduledTask | Where-Object {$_.TaskName -like "SYAGA-ATLAS-*"}

if ($tasks.Count -eq 2) {
    Write-Host "[OK] Les 2 tâches sont installées :" -ForegroundColor Green
    foreach ($task in $tasks) {
        $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
        Write-Host "  - $($task.TaskName) : $($task.State)" -ForegroundColor Green
    }
} else {
    Write-Host "[WARNING] Nombre de tâches incorrect : $($tasks.Count)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "         INSTALLATION RÉUSSIE !" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Version installée : v$VERSION" -ForegroundColor White
Write-Host "Architecture      : Professionnelle avec mutex" -ForegroundColor White
Write-Host "Auto-Update       : Actif (vérification/minute)" -ForegroundColor White
Write-Host "État persistant   : updater-state.json" -ForegroundColor White
Write-Host ""