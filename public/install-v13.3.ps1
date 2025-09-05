# ════════════════════════════════════════════════════
# ATLAS v13.3 - INSTALLATION AVEC LOGS SHAREPOINT COMPLETS
# ════════════════════════════════════════════════════

param(
    [switch]$Check,
    [switch]$Uninstall
)

$VERSION = "13.3"
$BASE_URL = "https://white-river-053fc6703.2.azurestaticapps.net/public"

# Configuration SharePoint pour logs d'installation
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

# Buffer logs d'installation
$script:InstallationLogs = ""

# ════════════════════════════════════════════════════
# FONCTION LOG AVEC REMONTÉE SHAREPOINT
# ════════════════════════════════════════════════════
function Write-InstallLog {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [INSTALL-$VERSION] [$Level] $Message"
    
    # Ajouter au buffer
    $script:InstallationLogs += "$logEntry`r`n"
    
    # Afficher
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "CRITICAL" { Write-Host $logEntry -ForegroundColor Magenta }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Cyan }
        default { Write-Host $logEntry }
    }
}

# ════════════════════════════════════════════════════
# FONCTION REMONTÉE LOGS SHAREPOINT
# ════════════════════════════════════════════════════
function Send-InstallationLogs {
    param($FinalStatus, $ErrorDetails = $null)
    
    try {
        Write-InstallLog "Remontée logs installation vers SharePoint..." "DEBUG"
        
        # Token SharePoint
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $token = $tokenResponse.access_token
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
        }
        
        # Créer header détaillé pour logs
        $hostname = $env:COMPUTERNAME
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        $detailedHeader = @"
════════════════════════════════════════════════════
ATLAS INSTALLATION LOG v$VERSION
════════════════════════════════════════════════════
Hostname: $hostname
Time: $currentTime
Status: $FinalStatus
$(if ($ErrorDetails) { "Error: $ErrorDetails" })

COMPLETE INSTALLATION LOG:
════════════════════════════════════════════════════
"@
        
        # Logs complets avec header
        $fullInstallationLogs = $detailedHeader + "`r`n" + $script:InstallationLogs
        
        # Informations système
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        # Créer entrée SharePoint avec TOUS les logs d'installation
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = "$hostname-INSTALL-$VERSION"
            Hostname = $hostname
            IPAddress = $ip
            State = $FinalStatus
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = "INSTALL-$VERSION"
            CPUUsage = 0
            MemoryUsage = 0
            DiskSpaceGB = 0
            Logs = $fullInstallationLogs
            Notes = "Installation v$VERSION - Status: $FinalStatus - Time: $currentTime"
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Envoyer à SharePoint
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-InstallLog "TOUS les logs d'installation remontés dans SharePoint pour auto-analyse" "SUCCESS"
        
    } catch {
        Write-InstallLog "Erreur remontée logs: $_" "ERROR"
    }
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ATLAS v$VERSION - LOGS SHAREPOINT COMPLETS" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-InstallLog "DÉBUT INSTALLATION v$VERSION" "SUCCESS"
Write-InstallLog "Hostname: $env:COMPUTERNAME" "INFO"

# Désinstallation
if ($Uninstall) {
    Write-InstallLog "DÉSINSTALLATION demandée" "WARNING"
    
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
    
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -ErrorAction SilentlyContinue
    
    Remove-Item -Path "C:\SYAGA-ATLAS" -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-InstallLog "ATLAS désinstallé" "SUCCESS"
    Send-InstallationLogs "UNINSTALLED"
    
    Write-Host ""
    Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
    Read-Host
    exit 0
}

# Vérification seulement
if ($Check) {
    Write-InstallLog "VÉRIFICATION demandée" "INFO"
    
    $agentPath = "C:\SYAGA-ATLAS\agent.ps1"
    $updaterPath = "C:\SYAGA-ATLAS\updater.ps1"
    
    # Vérifier les fichiers
    if (Test-Path $agentPath) {
        $agentContent = Get-Content $agentPath -First 5 | Out-String
        if ($agentContent -match 'Version\s*=\s*"([^"]+)"') {
            Write-InstallLog "Agent v$($matches[1]) trouvé" "SUCCESS"
        } else {
            Write-InstallLog "Agent trouvé mais version illisible" "WARNING"
        }
    } else {
        Write-InstallLog "Agent NON TROUVÉ" "ERROR"
    }
    
    if (Test-Path $updaterPath) {
        $updaterContent = Get-Content $updaterPath -First 5 | Out-String
        if ($updaterContent -match 'Version\s*=\s*"([^"]+)"') {
            Write-InstallLog "Updater v$($matches[1]) trouvé" "SUCCESS"
        } else {
            Write-InstallLog "Updater trouvé mais version illisible" "WARNING"
        }
    } else {
        Write-InstallLog "Updater NON TROUVÉ" "ERROR"
    }
    
    # Vérifier l'état de l'updater
    $statePath = "C:\SYAGA-ATLAS\updater-state.json"
    if (Test-Path $statePath) {
        try {
            $state = Get-Content $statePath -Raw | ConvertFrom-Json
            Write-InstallLog "État updater : $($state.Status)" "SUCCESS"
            Write-InstallLog "Version actuelle : $($state.CurrentVersion)" "INFO"
            Write-InstallLog "Dernière vérification : $($state.LastCheck)" "INFO"
        } catch {
            Write-InstallLog "État updater illisible: $_" "ERROR"
        }
    } else {
        Write-InstallLog "État updater NON TROUVÉ" "ERROR"
    }
    
    # Vérifier les tâches
    $agentTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    $updaterTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
    
    if ($agentTask) {
        Write-InstallLog "Tâche Agent : $($agentTask.State)" "SUCCESS"
    } else {
        Write-InstallLog "Tâche Agent NON TROUVÉE" "ERROR"
    }
    
    if ($updaterTask) {
        Write-InstallLog "Tâche Updater : $($updaterTask.State)" "SUCCESS"
    } else {
        Write-InstallLog "Tâche Updater NON TROUVÉE" "ERROR"
    }
    
    Send-InstallationLogs "CHECK_COMPLETED"
    
    Write-Host ""
    Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
    Read-Host
    exit 0
}

# INSTALLATION PRINCIPALE
$atlasPath = "C:\SYAGA-ATLAS"
$logsPath = "$atlasPath\logs"

Write-InstallLog "Création structure dossiers..." "INFO"

# Créer les dossiers
if (!(Test-Path $atlasPath)) {
    New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null
    Write-InstallLog "Dossier créé : $atlasPath" "SUCCESS"
} else {
    Write-InstallLog "Dossier existe : $atlasPath" "SUCCESS"
}

if (!(Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    Write-InstallLog "Dossier logs créé : $logsPath" "SUCCESS"
}

# 1. TÉLÉCHARGER AGENT v13.0 (stable)
Write-InstallLog "[1/6] Téléchargement agent v13.0..." "INFO"

$agentUrl = "$BASE_URL/agent-v13.0.ps1"
$agentPath = "$atlasPath\agent.ps1"

# Backup si existe
if (Test-Path $agentPath) {
    $backupPath = "$atlasPath\agent_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    Copy-Item $agentPath $backupPath -Force
    Write-InstallLog "Backup agent créé : $backupPath" "SUCCESS"
}

try {
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing
    $agentSize = (Get-Item $agentPath).Length
    Write-InstallLog "Agent v13.0 téléchargé ($agentSize bytes)" "SUCCESS"
    
    # Vérifier version téléchargée
    $downloadedAgent = Get-Content $agentPath -First 10 | Out-String
    if ($downloadedAgent -match 'Version\s*=\s*"([^"]+)"') {
        Write-InstallLog "Version agent téléchargée : v$($matches[1])" "SUCCESS"
    } else {
        Write-InstallLog "ATTENTION: Version agent non détectée dans le fichier téléchargé" "WARNING"
    }
    
} catch {
    Write-InstallLog "ERREUR téléchargement agent : $_" "ERROR"
    Send-InstallationLogs "FAILED" "Agent download failed: $_"
    Write-Host ""
    Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
    Read-Host
    exit 1
}

# 2. TÉLÉCHARGER UPDATER v13.0 (stable)
Write-InstallLog "[2/6] Téléchargement updater v13.0..." "INFO"

$updaterUrl = "$BASE_URL/updater-v13.0.ps1"
$updaterPath = "$atlasPath\updater.ps1"

# Backup si existe
if (Test-Path $updaterPath) {
    $backupPath = "$atlasPath\updater_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    Copy-Item $updaterPath $backupPath -Force
    Write-InstallLog "Backup updater créé : $backupPath" "SUCCESS"
}

try {
    Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
    $updaterSize = (Get-Item $updaterPath).Length
    Write-InstallLog "Updater v13.0 téléchargé ($updaterSize bytes)" "SUCCESS"
    
    # Vérifier version téléchargée
    $downloadedUpdater = Get-Content $updaterPath -First 10 | Out-String
    if ($downloadedUpdater -match 'Version\s*=\s*"([^"]+)"') {
        Write-InstallLog "Version updater téléchargée : v$($matches[1])" "SUCCESS"
    } else {
        Write-InstallLog "ATTENTION: Version updater non détectée dans le fichier téléchargé" "WARNING"
    }
    
} catch {
    Write-InstallLog "ERREUR téléchargement updater : $_" "ERROR"
    Send-InstallationLogs "FAILED" "Updater download failed: $_"
    Write-Host ""
    Write-Host "Appuyez sur Entrée pour fermer..." -ForegroundColor Yellow
    Read-Host
    exit 1
}

# 3. SUPPRIMER ANCIENNES TÂCHES
Write-InstallLog "[3/6] Suppression anciennes tâches..." "INFO"

$oldAgentTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
$oldUpdaterTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue

if ($oldAgentTask) {
    Write-InstallLog "Ancienne tâche Agent trouvée : $($oldAgentTask.State)" "INFO"
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -ErrorAction SilentlyContinue
    Write-InstallLog "Ancienne tâche Agent supprimée" "SUCCESS"
}

if ($oldUpdaterTask) {
    Write-InstallLog "Ancienne tâche Updater trouvée : $($oldUpdaterTask.State)" "INFO"
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -ErrorAction SilentlyContinue
    Write-InstallLog "Ancienne tâche Updater supprimée" "SUCCESS"
}

Write-InstallLog "Nettoyage tâches terminé" "SUCCESS"

# 4. CRÉER TÂCHE AGENT
Write-InstallLog "[4/6] Création tâche Agent..." "INFO"

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

    Write-InstallLog "Tâche Agent créée avec succès (toutes les 2 minutes)" "SUCCESS"
} catch {
    Write-InstallLog "ERREUR création tâche Agent : $_" "ERROR"
    Send-InstallationLogs "FAILED" "Agent task creation failed: $_"
}

# 5. CRÉER TÂCHE UPDATER
Write-InstallLog "[5/6] Création tâche Updater..." "INFO"

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

    Write-InstallLog "Tâche Updater créée avec succès (toutes les minutes)" "SUCCESS"
} catch {
    Write-InstallLog "ERREUR création tâche Updater : $_" "ERROR"
    Send-InstallationLogs "FAILED" "Updater task creation failed: $_"
}

# 6. DÉMARRER LES TÂCHES
Write-InstallLog "[6/6] Démarrage des tâches..." "INFO"

try {
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction Stop
    Write-InstallLog "Tâche Agent démarrée" "SUCCESS"
} catch {
    Write-InstallLog "ATTENTION: Démarrage tâche Agent: $_" "WARNING"
}

try {
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction Stop
    Write-InstallLog "Tâche Updater démarrée" "SUCCESS"
} catch {
    Write-InstallLog "ATTENTION: Démarrage tâche Updater: $_" "WARNING"
}

# VÉRIFICATION FINALE DÉTAILLÉE
Write-InstallLog "VÉRIFICATION FINALE..." "INFO"

$finalTasks = Get-ScheduledTask | Where-Object {$_.TaskName -like "SYAGA-ATLAS-*"}
Write-InstallLog "Nombre de tâches trouvées : $($finalTasks.Count)" "INFO"

if ($finalTasks.Count -eq 2) {
    Write-InstallLog "✓ LES 2 TÂCHES SONT INSTALLÉES" "SUCCESS"
    foreach ($task in $finalTasks) {
        try {
            $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
            Write-InstallLog "- $($task.TaskName) : $($task.State)" "SUCCESS"
            Write-InstallLog "  Dernière exécution : $($info.LastRunTime)" "INFO"
            Write-InstallLog "  Prochaine exécution : $($info.NextRunTime)" "INFO"
        } catch {
            Write-InstallLog "- $($task.TaskName) : État inconnu ($_)" "WARNING"
        }
    }
    
    # Envoyer logs avec succès
    Send-InstallationLogs "SUCCESS"
    
} else {
    Write-InstallLog "✗ PROBLÈME: Nombre de tâches incorrect : $($finalTasks.Count)" "ERROR"
    foreach ($task in $finalTasks) {
        Write-InstallLog "- Tâche trouvée : $($task.TaskName)" "INFO"
    }
    
    # Envoyer logs avec erreur
    Send-InstallationLogs "FAILED" "Wrong number of tasks: $($finalTasks.Count)"
}

Write-InstallLog "INSTALLATION TERMINÉE" "SUCCESS"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " ATLAS v$VERSION INSTALLÉ AVEC LOGS COMPLETS" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "TOUS LES LOGS D'INSTALLATION REMONTÉS DANS SHAREPOINT" -ForegroundColor Yellow
Write-Host "pour auto-analyse et debugging !" -ForegroundColor Yellow
Write-Host ""
Write-Host "=== INSTALLATION TERMINÉE ===" -ForegroundColor Green
Write-Host "Appuyez sur Entrée pour fermer cette fenêtre..." -ForegroundColor Yellow
Read-Host
Write-Host "Fermeture..." -ForegroundColor Gray
Start-Sleep -Seconds 2