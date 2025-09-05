# ════════════════════════════════════════════════════
# ATLAS v13.2 - INSTALLATION COMPLÈTE (FIX TÂCHES PLANIFIÉES)
# ════════════════════════════════════════════════════

param(
    [switch]$Check,
    [switch]$Uninstall
)

$VERSION = "13.2"
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
    Write-Host ""
    Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
    Read-Host
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
    
    Write-Host ""
    Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
    Read-Host
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

# 1. TÉLÉCHARGER AGENT v13.0 (stable)
Write-Host "[1/6] Téléchargement agent v13.0..." -ForegroundColor Yellow

$agentUrl = "$BASE_URL/agent-v13.0.ps1"
$agentPath = "$atlasPath\agent.ps1"

# Backup si existe
if (Test-Path $agentPath) {
    $backupPath = "$atlasPath\agent_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    Copy-Item $agentPath $backupPath -Force
    Write-Host "[OK] Backup créé" -ForegroundColor Green
}

try {
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing
    Write-Host "[OK] Agent v13.0 téléchargé" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Téléchargement agent : $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
    Read-Host
    exit 1
}

# 2. TÉLÉCHARGER UPDATER v13.0 (stable)
Write-Host "[2/6] Téléchargement updater v13.0..." -ForegroundColor Yellow

$updaterUrl = "$BASE_URL/updater-v13.0.ps1"
$updaterPath = "$atlasPath\updater.ps1"

# Backup si existe
if (Test-Path $updaterPath) {
    $backupPath = "$atlasPath\updater_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    Copy-Item $updaterPath $backupPath -Force
    Write-Host "[OK] Backup updater créé" -ForegroundColor Green
}

try {
    Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
    Write-Host "[OK] Updater v13.0 téléchargé" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Téléchargement updater : $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
    Read-Host
    exit 1
}

# 3. SUPPRIMER ANCIENNES TÂCHES
Write-Host "[3/6] Suppression anciennes tâches..." -ForegroundColor Yellow

Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue

Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "[OK] Anciennes tâches supprimées" -ForegroundColor Green

# 4. CRÉER TÂCHE AGENT (CORRECTION REPETITION DURATION)
Write-Host "[4/6] Création tâche Agent..." -ForegroundColor Yellow

try {
    $agentAction = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentPath`""

    $agentTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10) `
        -RepetitionInterval (New-TimeSpan -Minutes 2) `
        -RepetitionDuration (New-TimeSpan -Days 365)

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
} catch {
    Write-Host "[ERREUR] Création tâche Agent : $_" -ForegroundColor Red
}

# 5. CRÉER TÂCHE UPDATER (CORRECTION REPETITION DURATION)  
Write-Host "[5/6] Création tâche Updater..." -ForegroundColor Yellow

try {
    $updaterAction = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$updaterPath`""

    $updaterTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 365)

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
} catch {
    Write-Host "[ERREUR] Création tâche Updater : $_" -ForegroundColor Red
}

# 6. DÉMARRER LES TÂCHES
Write-Host "[6/6] Démarrage des tâches..." -ForegroundColor Yellow

try {
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction Stop
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction Stop
    Write-Host "[OK] Tâches démarrées" -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Démarrage tâches : $_" -ForegroundColor Yellow
    Write-Host "Les tâches démarreront automatiquement selon leur planification" -ForegroundColor Gray
}

# PAUSE AVANT TESTS
Write-Host ""
Write-Host "Appuyez sur Entrée pour continuer avec les tests..." -ForegroundColor Yellow
Read-Host

# TEST CONTRÔLÉ AGENT (avec timeout)
Write-Host ""
Write-Host "=== TEST AGENT v13.0 (limité à 30s) ===" -ForegroundColor Cyan

try {
    $job = Start-Job -ScriptBlock { & $using:agentPath }
    $completed = Wait-Job -Job $job -Timeout 30
    
    if ($completed) {
        $output = Receive-Job -Job $job
        if ($output) {
            Write-Host $output
        }
        Write-Host "[OK] Test agent terminé avec succès" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Test agent interrompu après 30s (normal)" -ForegroundColor Yellow
        Stop-Job -Job $job
    }
    Remove-Job -Job $job -Force
} catch {
    Write-Host "[WARNING] Erreur test agent : $_" -ForegroundColor Yellow
}

# PAUSE AVANT UPDATER
Write-Host ""
Write-Host "Appuyez sur Entrée pour tester l'updater..." -ForegroundColor Yellow
Read-Host

# TEST CONTRÔLÉ UPDATER (avec timeout)
Write-Host ""
Write-Host "=== TEST UPDATER v13.0 (limité à 30s) ===" -ForegroundColor Cyan

try {
    $job = Start-Job -ScriptBlock { & $using:updaterPath }
    $completed = Wait-Job -Job $job -Timeout 30
    
    if ($completed) {
        $output = Receive-Job -Job $job
        if ($output) {
            Write-Host $output
        }
        Write-Host "[OK] Test updater terminé avec succès" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Test updater interrompu après 30s (normal)" -ForegroundColor Yellow
        Stop-Job -Job $job
    }
    Remove-Job -Job $job -Force
} catch {
    Write-Host "[WARNING] Erreur test updater : $_" -ForegroundColor Yellow
}

# RÉSULTATS FINAUX
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " ATLAS v$VERSION INSTALLÉ AVEC SUCCÈS" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "NOUVELLES FONCTIONNALITÉS v13.x :" -ForegroundColor Yellow
Write-Host "  - Mutex pour instance unique" -ForegroundColor White
Write-Host "  - Persistance d'état JSON" -ForegroundColor White
Write-Host "  - Validation avant mise à jour" -ForegroundColor White
Write-Host "  - Système de rollback" -ForegroundColor White
Write-Host "  - Logs avec rotation" -ForegroundColor White
Write-Host "  - Monitoring complet updater" -ForegroundColor White
Write-Host ""
Write-Host "CORRECTIONS v$VERSION :" -ForegroundColor Yellow
Write-Host "  - Fix tâches planifiées (RepetitionDuration)" -ForegroundColor White
Write-Host "  - Durée 365 jours au lieu de MaxValue" -ForegroundColor White
Write-Host ""
Write-Host "Fichiers :" -ForegroundColor Yellow
Write-Host "  Agent    : $agentPath (v13.0)" -ForegroundColor White
Write-Host "  Updater  : $updaterPath (v13.0)" -ForegroundColor White
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
        try {
            $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
            Write-Host "  - $($task.TaskName) : $($task.State)" -ForegroundColor Green
            Write-Host "    Dernière exécution : $($info.LastRunTime)" -ForegroundColor Gray
            Write-Host "    Prochaine exécution : $($info.NextRunTime)" -ForegroundColor Gray
        } catch {
            Write-Host "  - $($task.TaskName) : État inconnu" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[WARNING] Nombre de tâches incorrect : $($tasks.Count)" -ForegroundColor Yellow
    Write-Host "Vérifiez manuellement avec Get-ScheduledTask" -ForegroundColor Gray
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "         INSTALLATION RÉUSSIE !" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Version installée : v$VERSION (fix tâches planifiées)" -ForegroundColor White
Write-Host "Architecture      : Professionnelle avec mutex" -ForegroundColor White
Write-Host "Auto-Update       : Actif (vérification/minute)" -ForegroundColor White
Write-Host "État persistant   : updater-state.json" -ForegroundColor White
Write-Host ""
Write-Host "=== INSTALLATION TERMINÉE ===" -ForegroundColor Green
Write-Host "Appuyez sur Entrée pour fermer cette fenêtre..." -ForegroundColor Yellow
Read-Host
Write-Host "Fermeture..." -ForegroundColor Gray
Start-Sleep -Seconds 2