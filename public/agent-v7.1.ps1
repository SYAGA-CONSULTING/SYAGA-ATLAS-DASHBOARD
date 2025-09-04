# ATLAS Agent v7.1 - Test AUTO-UPDATE avec nouvelle liste
$version = "7.1"
$configPath = "C:\SYAGA-ATLAS"
$rollbackTimeout = 5  # Minutes avant rollback automatique

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param($Message, $Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$ts] [$Level] $Message"
    if (!(Test-Path $configPath)) {
        New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    }
    Add-Content "$configPath\agent.log" -Value $log -Encoding UTF8
    $color = @{INFO="White"; OK="Green"; ERROR="Red"; UPDATE="Cyan"; WARNING="Yellow"; ROLLBACK="Magenta"; DEBUG="Gray"}[$Level]
    Write-Host $log -ForegroundColor $color
}

# FONCTION ROLLBACK TASK
function Test-RollbackCapability {
    Write-Log "[ROLLBACK] Test préalable du système de rollback..." "ROLLBACK"
    
    # Test 1: Vérifier qu'on peut créer une tâche
    try {
        $testTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Test" -EA SilentlyContinue
        if ($testTask) {
            Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Test" -Confirm:$false
        }
        
        # Créer tâche test simple
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-Command `"Write-Host 'Test'`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(60)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName "SYAGA-ATLAS-Test" -Action $action -Trigger $trigger -Principal $principal | Out-Null
        Write-Log "[ROLLBACK] ✅ Test 1: Création de tâche OK" "OK"
        
        # Nettoyer
        Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Test" -Confirm:$false
    } catch {
        Write-Log "[ROLLBACK] ❌ Test 1: Impossible de créer tâche: $_" "ERROR"
        return $false
    }
    
    # Test 2: Vérifier que le script de rollback peut être exécuté
    $backupFile = "$configPath\agent.backup.ps1"
    if (Test-Path $backupFile) {
        Write-Log "[ROLLBACK] ✅ Test 2: Fichier backup existe" "OK"
    } else {
        # Créer un backup temporaire pour le test
        if (Test-Path "$configPath\agent.ps1") {
            Copy-Item "$configPath\agent.ps1" $backupFile -Force
            Write-Log "[ROLLBACK] ✅ Test 2: Backup créé pour test" "OK"
        } else {
            Write-Log "[ROLLBACK] ⚠️ Test 2: Pas de fichier agent à backuper" "WARNING"
        }
    }
    
    # Test 3: Vérifier accès au fichier agent.ps1
    if (Test-Path "$configPath\agent.ps1") {
        try {
            $content = Get-Content "$configPath\agent.ps1" -First 1 -EA Stop
            Write-Log "[ROLLBACK] ✅ Test 3: Accès fichier agent OK" "OK"
        } catch {
            Write-Log "[ROLLBACK] ❌ Test 3: Impossible de lire agent.ps1: $_" "ERROR"
            return $false
        }
    }
    
    Write-Log "[ROLLBACK] ✅ TOUS LES TESTS PASSÉS - Rollback opérationnel" "OK"
    return $true
}

function Create-RollbackTask {
    param(
        [string]$FromVersion = $version,
        [string]$ToVersion = "unknown"
    )
    
    Write-Log "[ROLLBACK] Création tâche rollback (timeout: $rollbackTimeout min)" "ROLLBACK"
    
    # Créer script de rollback
    $rollbackScript = @"
`$configPath = 'C:\SYAGA-ATLAS'
Add-Content "`$configPath\rollback.log" -Value "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ROLLBACK TRIGGERED - v$ToVersion FAILED" -Encoding UTF8

# Restaurer backup
if (Test-Path "`$configPath\agent.backup.ps1") {
    Copy-Item "`$configPath\agent.backup.ps1" "`$configPath\agent.ps1" -Force
    Add-Content "`$configPath\rollback.log" -Value "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Restored v$FromVersion from backup" -Encoding UTF8
    
    # Créer flag de rollback
    @{
        RolledBack = `$true
        FailedVersion = "$ToVersion"
        RestoredVersion = "$FromVersion"
        RollbackTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json | Out-File "`$configPath\rollback.info" -Encoding UTF8
    
    # Nettoyer cette tâche
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:`$false
    
    Write-Host "ROLLBACK COMPLETE: v$ToVersion -> v$FromVersion" -ForegroundColor Red
} else {
    Add-Content "`$configPath\rollback.log" -Value "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: No backup found!" -Encoding UTF8
}
"@
    
    $rollbackScript | Out-File "$configPath\rollback_task.ps1" -Encoding UTF8
    
    # Créer tâche planifiée
    try {
        # Supprimer ancienne si existe
        $existing = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -EA SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:$false
            Write-Log "[ROLLBACK] Ancienne tâche supprimée" "WARNING"
        }
        
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-ExecutionPolicy Bypass -File `"$configPath\rollback_task.ps1`""
        
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($rollbackTimeout)
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" `
            -Action $action -Trigger $trigger -Principal $principal | Out-Null
        
        Write-Log "[ROLLBACK] ✅ Tâche créée - Exécution dans $rollbackTimeout minutes" "OK"
        Write-Log "[ROLLBACK] Si v$ToVersion stable, la tâche sera annulée automatiquement" "WARNING"
        
        return $true
    } catch {
        Write-Log "[ROLLBACK] ❌ Erreur création tâche: $_" "ERROR"
        return $false
    }
}

function Cancel-RollbackTask {
    Write-Log "[ROLLBACK] Annulation tâche rollback - Version stable confirmée" "OK"
    try {
        Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:$false -EA Stop
        Write-Log "[ROLLBACK] ✅ Tâche rollback supprimée" "OK"
        
        # Nettoyer fichiers temporaires
        if (Test-Path "$configPath\rollback_task.ps1") {
            Remove-Item "$configPath\rollback_task.ps1" -Force
        }
    } catch {
        Write-Log "[ROLLBACK] Info: $_" "DEBUG"
    }
}

function Check-RollbackInfo {
    # Rollback info code here
    if (Test-Path "$configPath\rollback.info") {
        try {
            $Info = Get-Content "$configPath\rollback.info" -Raw | ConvertFrom-Json
            if ($Info.RolledBack) {
                Write-Log "!!! ROLLBACK DETECTE !!!" "ROLLBACK"
                Write-Log "Version échouée: v$($Info.FailedVersion)" "ERROR"
                Write-Log "Version restaurée: v$($Info.RestoredVersion)" "OK"
                Write-Log "Heure rollback: $($Info.RollbackTime)" "WARNING"
                
                # Sauvegarder pour rapport
                $script:rollbackReport = $Info
                
                # Supprimer le flag après lecture
                Remove-Item "$configPath\rollback.info" -Force
                return $true
            }
        } catch {
            Write-Log "Erreur lecture rollback.info: $_" "DEBUG"
        }
    }
    return $false
    
    $script:rollbackReport = $Info
}

Write-Log "===== Agent ATLAS v$version DEMARRE =====" "OK"
Write-Log "[v7.1] Test AUTO-UPDATE avec architecture liste séparée" "UPDATE"

# 1. Vérifier si on vient d'un rollback
$wasRolledBack = Check-RollbackInfo

# 2. Vérifier si on vient d'un update récent
if (-not $wasRolledBack) {
    $rollbackTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -EA SilentlyContinue
    if ($rollbackTask) {
        Write-Log "[UPDATE] Tâche rollback détectée - Update récent, test de stabilité..." "WARNING"
        # On va tester avec le heartbeat si tout fonctionne
    }
}

# Charger config si existe
$configFile = "$configPath\config.json"
if (Test-Path $configFile) {
    $config = Get-Content $configFile -Raw -EA SilentlyContinue | ConvertFrom-Json -EA SilentlyContinue
    if ($config) {
        Write-Log "Config chargée: $($config.ClientName) / $($config.ServerType)" "OK"
    }
}

# FONCTION AUTO-UPDATE - v7.1 AVEC LISTE SÉPARÉE
function Check-Update {
    Write-Log "Check auto-update v$version..." "UPDATE"
    Write-Log "[UPDATE] Utilisation liste ATLAS-Commands" "DEBUG"
    
    try {
        $tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        $clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
        $cs = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
        
        $body = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($cs))
            resource = "00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -ContentType "application/x-www-form-urlencoded" -Body $body -EA Stop
        
        $token = $tokenResponse.access_token
        Write-Log "[UPDATE] Token obtenu" "DEBUG"
        
        # v7.1 - NOUVELLE LISTE ATLAS-Commands
        $hostname = $env:COMPUTERNAME
        $commandsListId = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"  # Liste ATLAS-Commands
        
        # Rechercher commandes PENDING pour ce serveur ou ALL
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$commandsListId')/items?`$filter=Status eq 'PENDING'&`$top=10&`$orderby=Created desc"
        
        Write-Log "[UPDATE] Vérification liste ATLAS-Commands (ID: $commandsListId)" "UPDATE"
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        try {
            $items = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET -EA Stop
            Write-Log "[UPDATE] $($items.d.results.Count) commande(s) PENDING trouvée(s)" "UPDATE"
        } catch {
            Write-Log "[UPDATE] Erreur accès liste commandes: $_" "ERROR"
            return
        }
        
        foreach ($item in $items.d.results) {
            # Vérifier si la commande nous concerne
            $targetHost = $item.TargetHostname
            if ($targetHost -eq "ALL" -or $targetHost -eq $hostname) {
                if ($item.CommandType -eq "UPDATE") {
                    Write-Log ">>> COMMANDE UPDATE DÉTECTÉE <<<" "UPDATE"
                    Write-Log "[UPDATE] ID: $($item.Id)" "UPDATE"
                    Write-Log "[UPDATE] Target: $targetHost" "UPDATE"
                    Write-Log "[UPDATE] Version cible: $($item.TargetVersion)" "UPDATE"
                    Write-Log "[UPDATE] Créée par: $($item.CreatedBy)" "UPDATE"
                    
                    $targetVersion = if ($item.TargetVersion) { $item.TargetVersion } else { "7.1" }
                    
                    # Vérifier si c'est vraiment une mise à jour
                    if ($targetVersion -eq $version) {
                        Write-Log "[UPDATE] Déjà en v$version - Ignorer" "WARNING"
                        continue
                    }
                    
                    Write-Log "[UPDATE] Mise à jour v$version → v$targetVersion" "UPDATE"
                    
                    # IMPORTANT: TESTER le rollback AVANT tout
                    Write-Log "[UPDATE] Phase 1: Test du système de rollback" "UPDATE"
                    $rollbackTestOk = Test-RollbackCapability
                    if (-not $rollbackTestOk) {
                        Write-Log "[UPDATE] ❌ ANNULATION - Rollback non opérationnel" "ERROR"
                        Write-Log "[UPDATE] L'update est annulé par sécurité" "ERROR"
                        return
                    }
                    
                    # Créer tâche rollback
                    Write-Log "[UPDATE] Phase 2: Création tâche rollback" "UPDATE"
                    $rollbackCreated = Create-RollbackTask -FromVersion $version -ToVersion $targetVersion
                    if (-not $rollbackCreated) {
                        Write-Log "[UPDATE] ❌ ANNULATION - Impossible de créer tâche" "ERROR"
                        return
                    }
                    
                    # Vérifier que la tâche existe vraiment
                    $task = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -EA SilentlyContinue
                    if ($task) {
                        Write-Log "[UPDATE] ✅ Tâche rollback confirmée: $($task.State)" "OK"
                        Write-Log "[UPDATE] Phase 3: Procéder à l'update" "UPDATE"
                    } else {
                        Write-Log "[UPDATE] ❌ Tâche rollback introuvable - Update annulé" "ERROR"
                        return
                    }
                    
                    # Sauvegarder version actuelle
                    if (Test-Path "$configPath\agent.ps1") {
                        Copy-Item "$configPath\agent.ps1" "$configPath\agent.backup.ps1" -Force
                        Write-Log "Backup créé: agent.backup.ps1" "OK"
                    }
                    
                    # Télécharger nouvelle version
                    $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$targetVersion.ps1"
                    Write-Log "Download: $newAgentUrl" "UPDATE"
                    
                    try {
                        $newAgent = Invoke-RestMethod -Uri $newAgentUrl -EA Stop
                        $newAgent | Out-File "$configPath\agent.ps1" -Encoding UTF8 -Force
                        Write-Log "!!! AGENT MIS A JOUR VERS v$targetVersion !!!" "OK"
                        
                        # v7.1 - Marquer la commande comme EXECUTED dans ATLAS-Commands
                        try {
                            $updateUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($($item.Id))"
                            
                            $updateData = @{
                                __metadata = @{ type = "SP.Data.ATLASCommandsListItem" }
                                Status = "EXECUTED"
                                ExecutedBy = if ($item.ExecutedBy) { "$($item.ExecutedBy),$hostname" } else { $hostname }
                            }
                            
                            $updateHeaders = $headers.Clone()
                            $updateHeaders["IF-MATCH"] = "*"
                            $updateHeaders["X-HTTP-Method"] = "MERGE"
                            $updateHeaders["Content-Type"] = "application/json;odata=verbose"
                            
                            Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body ($updateData | ConvertTo-Json) -EA Stop
                            Write-Log "[UPDATE] Commande marquée EXECUTED dans ATLAS-Commands" "OK"
                        } catch {
                            Write-Log "[UPDATE] Note: Impossible de marquer commande: $_" "DEBUG"
                        }
                        
                        Write-Log "Redémarrage avec v$targetVersion dans quelques secondes..." "UPDATE"
                        Write-Log "[ROLLBACK] Tâche armée pour dans $rollbackTimeout minutes" "ROLLBACK"
                        
                        # Arrêt pour redémarrage
                        exit 0
                        
                    } catch {
                        Write-Log "Erreur download: $_" "ERROR"
                    }
                }
            }
        }
    } catch {
        Write-Log "Erreur check update: $_" "ERROR"
    }
}

# FONCTION HEARTBEAT
function Send-Heartbeat {
    try {
        $hostname = $env:COMPUTERNAME
        
        # Get token
        $tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        $clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
        $cs = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
        
        $body = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($cs))
            resource = "00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -ContentType "application/x-www-form-urlencoded" -Body $body -EA Stop
        
        $token = $tokenResponse.access_token
        
        # Métriques
        $cpu = [Math]::Round((Get-Counter '\Processeur(_Total)\% temps processeur' -EA SilentlyContinue).CounterSamples[0].CookedValue, 0)
        $memUsed = [Math]::Round((Get-Process | Measure-Object WorkingSet -Sum).Sum / 1GB, 1)
        $memTotal = [Math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        $memUsedPct = [Math]::Round($memUsed / $memTotal * 100, 0)
        
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [Math]::Round($disk.FreeSpace / 1GB, 1)
        $diskTotalGB = [Math]::Round($disk.Size / 1GB, 1)
        $diskUsedPct = [Math]::Round((($diskTotalGB - $diskFreeGB) / $diskTotalGB) * 100, 0)
        
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $uptimeDays = [Math]::Round($uptime.TotalDays, 1)
        
        # Veeam status
        $veeamStatus = "NoVeeam"
        $veeamService = Get-Service -Name "VeeamBackupSvc" -EA SilentlyContinue
        if ($veeamService) {
            $veeamStatus = if ($veeamService.Status -eq "Running") { "VeeamOK" } else { "VeeamStopped" }
        }
        
        # Hyper-V status
        $hvStatus = "N/A"
        $hvService = Get-Service -Name "vmms" -EA SilentlyContinue
        if ($hvService) {
            $hvStatus = if ($hvService.Status -eq "Running") { "Running" } else { "Stopped" }
        }
        
        $statusText = "v$version | Up:${uptimeDays}d | $hvStatus"
        if ($script:rollbackReport) {
            $statusText = "ROLLBACK: $($script:rollbackReport.FailedVersion)→$($script:rollbackReport.RestoredVersion) | $statusText"
        }
        
        # Préparer données - v7.1 SANS CPUPercent
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        $data = @{
            __metadata = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            State = "Online"
            AgentVersion = $version
            LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            # CPUPercent retiré car cause error 400
            DiskSpaceGB = $diskFreeGB
            VeeamStatus = $statusText
        }
        
        # Chercher entrée existante
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items?`$filter=Hostname eq '$hostname'"
        $existing = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET -EA SilentlyContinue
        
        if ($existing -and $existing.d.results.Count -gt 0) {
            # UPDATE
            $itemId = $existing.d.results[0].Id
            $updateUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items($itemId)"
            $headers["IF-MATCH"] = "*"
            $headers["X-HTTP-Method"] = "MERGE"
            $headers["Content-Type"] = "application/json;odata=verbose"
            
            Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method POST -Body ($data | ConvertTo-Json -Depth 10)
            Write-Log "[v$version] UPDATE OK - $statusText" "OK"
        } else {
            # CREATE
            $createUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
            $headers["Content-Type"] = "application/json;odata=verbose"
            
            Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body ($data | ConvertTo-Json -Depth 10)
            Write-Log "[v$version] CREATE OK - $statusText" "OK"
        }
        
        Write-Log "CPU:${cpu}% RAM:${memUsedGB}/${memTotalGB}GB (${memUsedPct}%) Disk:${diskFreeGB}GB free (${diskUsedPct}% used)"
        Write-Log "[METRICS] Heartbeat envoyé avec succès vers SharePoint" "OK"
        
        return $true
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
        return $false
    }
}

# EXÉCUTION PRINCIPALE

# Si tâche rollback active et heartbeat OK = annuler rollback
$rollbackTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -EA SilentlyContinue
if ($rollbackTask) {
    Write-Log "[UPDATE] Test heartbeat pour valider stabilité..." "UPDATE"
    $heartbeatOk = Send-Heartbeat
    
    if ($heartbeatOk) {
        Write-Log "✅ v$version CONFIRMÉE STABLE - Annulation rollback" "OK"
        Cancel-RollbackTask
    } else {
        Write-Log "❌ v$version INSTABLE - Rollback dans $rollbackTimeout minutes" "ERROR"
    }
} else {
    # Pas de rollback en cours, heartbeat normal
    Send-Heartbeat
}

# Check update - FONCTION PRINCIPALE
Check-Update

Write-Log "===== Agent v$version TERMINE ====="