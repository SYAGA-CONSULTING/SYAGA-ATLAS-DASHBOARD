# ════════════════════════════════════════════════════
# ATLAS v12.6 - INSTALLATION COMPLÈTE
# ════════════════════════════════════════════════════

param(
    [switch]$Check,
    [switch]$Uninstall
)

$VERSION = "12.6"
$BASE_URL = "https://white-river-053fc6703.2.azurestaticapps.net/public"

Write-Host ""
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ATLAS v$VERSION - LOGS ENRICHIS + TRACKING" -ForegroundColor Yellow
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

# Créer le dossier
if (!(Test-Path $atlasPath)) {
    New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null
    Write-Host "[OK] Dossier créé : $atlasPath" -ForegroundColor Green
} else {
    Write-Host "[OK] Dossier existe : $atlasPath" -ForegroundColor Green
}

# 1. TÉLÉCHARGER AGENT v12.6
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

# 2. TÉLÉCHARGER UPDATER v12.6
Write-Host "[2/6] Téléchargement updater v$VERSION..." -ForegroundColor Yellow

$updaterUrl = "$BASE_URL/updater-v$VERSION.ps1"
$updaterPath = "$atlasPath\updater.ps1"

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

# TEST IMMÉDIAT
Write-Host ""
Write-Host "=== TEST IMMÉDIAT ===" -ForegroundColor Cyan

& $agentPath

Write-Host ""
Write-Host "=== MARQUAGE COMMANDE v$VERSION ===" -ForegroundColor Cyan

& $updaterPath

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host " ATLAS v$VERSION INSTALLE AVEC SUCCES" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "NOUVEAUTES v$VERSION :" -ForegroundColor Yellow
Write-Host "  - Logs enrichis avec header structure" -ForegroundColor White
Write-Host "  - Tracking Agent + Updater separe" -ForegroundColor White
Write-Host "  - Buffer 15KB pour plus de logs" -ForegroundColor White
Write-Host "  - Auto-fix updater integre" -ForegroundColor White
Write-Host "  - Metriques detaillees (MB, GB)" -ForegroundColor White
Write-Host ""
Write-Host "Fichiers:" -ForegroundColor Yellow
Write-Host "  Agent    : $agentPath (v$VERSION)" -ForegroundColor White
Write-Host "  Updater  : $updaterPath (v$VERSION)" -ForegroundColor White
Write-Host "  Logs     : $atlasPath\atlas_log.txt" -ForegroundColor White
Write-Host ""
Write-Host "Commandes:" -ForegroundColor Yellow
Write-Host "  Verifier : .\install-v$VERSION.ps1 -Check" -ForegroundColor White
Write-Host "  Desinstaller : .\install-v$VERSION.ps1 -Uninstall" -ForegroundColor White
Write-Host ""

# VÉRIFICATION FINALE
$tasks = Get-ScheduledTask | Where-Object {$_.TaskName -like "SYAGA-ATLAS-*"}

if ($tasks.Count -eq 2) {
    Write-Host "[OK] Les 2 taches sont installees:" -ForegroundColor Green
    foreach ($task in $tasks) {
        $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
        Write-Host "  - $($task.TaskName) : $($task.State)" -ForegroundColor Green
    }
} else {
    Write-Host "[WARNING] Nombre de tâches incorrect: $($tasks.Count)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "         INSTALLATION RÉUSSIE !" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Version installée : v$VERSION" -ForegroundColor White
Write-Host "Auto-Update      : Actif (vérification/minute)" -ForegroundColor White
Write-Host ""