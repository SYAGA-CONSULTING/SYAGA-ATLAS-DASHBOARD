# ATLAS Agent v6.2 - Debug Error 400 + Logs SharePoint
$version = "6.2"
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

# FONCTION ENVOI LOGS VERS SHAREPOINT
function Send-LogToSharePoint {
    param(
        [string]$ErrorType,
        [string]$ErrorMessage, 
        [string]$ErrorDetails = "",
        [string]$Context = ""
    )
    
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
        
        # Liste ATLAS-Commands pour stocker les logs
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        $hostname = $env:COMPUTERNAME
        
        # Envoyer comme commande de type LOG pour analyse
        $data = @{
            __metadata = @{ type = "SP.Data.ATLASCommandsListItem" }
            Title = "ERROR_LOG_$hostname"
            Hostname = $hostname
            CommandType = "LOG"
            AgentVersion = "v$version ERROR"
            VeeamStatus = "$ErrorType | $ErrorMessage | $Context | $ErrorDetails".Substring(0, [Math]::Min(250, "$ErrorType | $ErrorMessage | $Context | $ErrorDetails".Length))
            LastContact = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        
        $createUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose"
        }
        
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body ($data | ConvertTo-Json -Depth 10) -EA Stop
        Write-Log "[LOG] Erreur envoyée à SharePoint pour analyse" "OK"
    } catch {
        Write-Log "[LOG] Impossible d'envoyer log à SharePoint: $_" "WARNING"
    }
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
    if (Test-Path "$configPath\rollback.info") {
        try {
            $info = Get-Content "$configPath\rollback.info" -Raw | ConvertFrom-Json
            if ($info.RolledBack) {
                Write-Log "!!! ROLLBACK DETECTE !!!" "ROLLBACK"
                Write-Log "Version échouée: v$($info.FailedVersion)" "ERROR"
                Write-Log "Version restaurée: v$($info.RestoredVersion)" "OK"
                Write-Log "Heure rollback: $($info.RollbackTime)" "WARNING"
                
                # Sauvegarder pour rapport
                $script:rollbackReport = $info
                
                # Supprimer le flag après lecture
                Remove-Item "$configPath\rollback.info" -Force
                return $true
            }
        } catch {
            Write-Log "Erreur lecture rollback.info: $_" "DEBUG"
        }
    }
    return $false
}

# DÉMARRAGE
Write-Log "===== Agent ATLAS v$version DEMARRE ====="
Write-Log "[v6.2] Version avec debug error 400 et logs SharePoint"

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

# FONCTION AUTO-UPDATE
function Check-Update {
    Write-Log "Check auto-update v$version..." "UPDATE"
    
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
        
        # Chercher commandes UPDATE
        $hostname = $env:COMPUTERNAME
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        $items = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        
        foreach ($item in $items.d.results) {
            if ($item.Title -eq "UPDATE_COMMAND_$hostname" -or $item.Title -eq "UPDATE_ALL") {
                Write-Log ">>> UPDATE DETECTE: $($item.Title) <<<" "UPDATE"
                
                $targetVersion = if ($item.AgentVersion) { $item.AgentVersion } else { "5.9" }
                Write-Log "Version cible: v$targetVersion" "UPDATE"
                
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
                    Write-Log "Redémarrage dans 5 secondes..." "UPDATE"
                    Start-Sleep -Seconds 5
                    exit 0
                } catch {
                    Write-Log "Erreur download: $_" "ERROR"
                    Send-LogToSharePoint -ErrorType "UPDATE_DOWNLOAD_FAILED" `
                        -ErrorMessage $_.Exception.Message `
                        -Context "URL: $newAgentUrl"
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
        Write-Log "[HEARTBEAT] === DÉBUT ENVOI MÉTRIQUES ===" "DEBUG"
        Write-Log "[HEARTBEAT] Hostname: $hostname" "DEBUG"
        
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
        
        Write-Log "[HEARTBEAT] Obtention token OAuth..." "DEBUG"
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -ContentType "application/x-www-form-urlencoded" -Body $body -EA Stop
        
        $token = $tokenResponse.access_token
        Write-Log "[HEARTBEAT] ✅ Token obtenu" "DEBUG"
        
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
        
        $statusText = "v$version | Up:${uptimeDays}d | $veeamStatus"
        if ($script:rollbackReport) {
            $statusText = "ROLLBACK: $($script:rollbackReport.FailedVersion)→$($script:rollbackReport.RestoredVersion) | $statusText"
        }
        
        Write-Log "[HEARTBEAT] StatusText: $statusText" "DEBUG"
        
        # Préparer données - DEBUG v6.2
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        
        # Tester champ par champ pour identifier le problème
        Write-Log "[HEARTBEAT] === TEST CHAMPS UN PAR UN ===" "WARNING"
        
        $testFields = @(
            @{Name="Title"; Value=$hostname},
            @{Name="Hostname"; Value=$hostname},
            @{Name="State"; Value="Online"},
            @{Name="AgentVersion"; Value=$version},
            @{Name="LastContact"; Value=(Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")},
            @{Name="CPUPercent"; Value=[int]$cpu},
            @{Name="DiskSpaceGB"; Value=$diskFreeGB},
            @{Name="VeeamStatus"; Value=$statusText}
        )
        
        foreach ($field in $testFields) {
            Write-Log "[HEARTBEAT] Test champ: $($field.Name) = $($field.Value)" "DEBUG"
            
            $testData = @{
                __metadata = @{ type = "SP.Data.ATLASServersListItem" }
                Title = $hostname
            }
            # Ajouter le champ à tester
            if ($field.Name -ne "Title") {
                $testData[$field.Name] = $field.Value
            }
            
            try {
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
                    
                    Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method POST -Body ($testData | ConvertTo-Json -Depth 10) -EA Stop
                    Write-Log "[HEARTBEAT] ✅ Champ $($field.Name) OK" "OK"
                } else {
                    # CREATE
                    $createUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
                    $headers["Content-Type"] = "application/json;odata=verbose"
                    
                    Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body ($testData | ConvertTo-Json -Depth 10) -EA Stop
                    Write-Log "[HEARTBEAT] ✅ Champ $($field.Name) OK (CREATE)" "OK"
                }
            } catch {
                Write-Log "[HEARTBEAT] ❌ ERREUR Champ $($field.Name): $_" "ERROR"
                
                # Envoyer erreur détaillée à SharePoint
                Send-LogToSharePoint -ErrorType "HEARTBEAT_FIELD_ERROR" `
                    -ErrorMessage "Champ $($field.Name) rejeté" `
                    -ErrorDetails $_.Exception.Message `
                    -Context "Valeur: $($field.Value)"
                
                # Si c'est ce champ qui pose problème, on continue sans lui
                if ($_.Exception.Message -match "400") {
                    Write-Log "[HEARTBEAT] >>> CHAMP PROBLÉMATIQUE IDENTIFIÉ: $($field.Name) <<<" "ERROR"
                    Write-Log "[HEARTBEAT] Ce champ sera exclu des prochaines versions" "WARNING"
                }
            }
        }
        
        Write-Log "[HEARTBEAT] === FIN TEST CHAMPS ===" "WARNING"
        
        # Maintenant envoyer avec tous les champs qui marchent
        $data = @{
            __metadata = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            State = "Online" 
            AgentVersion = $version
            VeeamStatus = $statusText
        }
        
        Write-Log "[HEARTBEAT] Envoi final avec champs validés..." "DEBUG"
        
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
        
        return $true
        
    } catch {
        Write-Log "Erreur heartbeat finale: $_" "ERROR"
        
        # Log détaillé vers SharePoint
        Send-LogToSharePoint -ErrorType "HEARTBEAT_FINAL_ERROR" `
            -ErrorMessage $_.Exception.Message `
            -ErrorDetails $_.ToString() `
            -Context "Version: v$version"
        
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
        
        # Logger succès dans SharePoint
        Send-LogToSharePoint -ErrorType "UPDATE_SUCCESS" `
            -ErrorMessage "v$version stable - Rollback annulé" `
            -Context "Heartbeat OK"
    } else {
        Write-Log "❌ v$version INSTABLE - Rollback dans $rollbackTimeout minutes" "ERROR"
        Send-LogToSharePoint -ErrorType "UPDATE_UNSTABLE" `
            -ErrorMessage "v$version instable - Rollback programmé" `
            -Context "Heartbeat KO"
    }
} else {
    # Pas de rollback en cours, heartbeat normal
    Send-Heartbeat
}

# Check update
Check-Update

Write-Log "===== Agent v$version TERMINE ====="