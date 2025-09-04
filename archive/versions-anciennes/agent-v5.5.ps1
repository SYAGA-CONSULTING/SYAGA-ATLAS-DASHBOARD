# ATLAS Agent v5.5 - Rollback Automatique avec Dead Man's Switch
$version = "5.5"
$configPath = "C:\SYAGA-ATLAS"
$rollbackTimeout = 5  # Minutes avant rollback automatique (5 min pour tenir dans le timeout Claude de 10 min)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Variables globales
$script:errorCount = 0
$script:lastKnownGoodVersion = "5.3"
$script:logBuffer = @()
$script:updateSuccess = $false

function Write-Log {
    param($Message, $Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$ts] [$Level] $Message"
    
    # Log local
    if (!(Test-Path $configPath)) {
        New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    }
    Add-Content "$configPath\agent.log" -Value $log -Encoding UTF8
    
    # Affichage console
    $color = @{
        INFO="White"; OK="Green"; ERROR="Red"; UPDATE="Cyan"; 
        WARNING="Yellow"; v55="Magenta"; CRITICAL="Red"; DEBUG="Gray"
    }[$Level]
    Write-Host $log -ForegroundColor $color
    
    # Buffer pour SharePoint
    if ($Level -in @("ERROR", "CRITICAL", "UPDATE", "v55", "WARNING")) {
        $script:logBuffer += @{
            Time = $ts
            Level = $Level
            Message = $Message
        }
    }
}

function Create-RollbackTask {
    param(
        [string]$FromVersion,
        [string]$ToVersion
    )
    
    Write-Log "Création tâche rollback de sécurité (timeout: $rollbackTimeout min)" "WARNING"
    
    # Script de rollback qui sera exécuté après timeout
    $rollbackScript = @"
# ROLLBACK AUTOMATIQUE - Dead Man's Switch
`$configPath = 'C:\SYAGA-ATLAS'
`$logFile = "`$configPath\rollback.log"

function Log {
    param(`$msg)
    "`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - `$msg" | Out-File `$logFile -Append -Encoding UTF8
}

Log "=== ROLLBACK AUTOMATIQUE DÉCLENCHÉ ==="
Log "Raison: Pas de confirmation de succès après $rollbackTimeout minutes"
Log "Version actuelle: $ToVersion"
Log "Rollback vers: $FromVersion"

# Sauvegarder les logs d'échec
if (Test-Path "`$configPath\agent.log") {
    Copy-Item "`$configPath\agent.log" "`$configPath\failed_v$ToVersion.log" -Force
    Log "Logs d'échec sauvegardés dans failed_v$ToVersion.log"
}

# Télécharger l'ancienne version stable
try {
    `$rollbackUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$FromVersion.ps1"
    Log "Téléchargement de `$rollbackUrl"
    
    `$oldAgent = Invoke-RestMethod -Uri `$rollbackUrl -EA Stop
    `$oldAgent | Out-File "`$configPath\agent.ps1" -Encoding UTF8 -Force
    
    Log "ROLLBACK RÉUSSI - Agent restauré vers v$FromVersion"
    
    # Créer un flag pour indiquer qu'un rollback a eu lieu
    @{
        RollbackDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        FailedVersion = "$ToVersion"
        RestoredVersion = "$FromVersion"
        Reason = "Timeout - Pas de confirmation après $rollbackTimeout minutes"
    } | ConvertTo-Json | Out-File "`$configPath\rollback_info.json" -Force
    
} catch {
    Log "ERREUR ROLLBACK: `$_"
}

# Supprimer cette tâche de rollback
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:`$false -EA SilentlyContinue

Log "=== FIN ROLLBACK ==="
"@
    
    # Sauvegarder le script
    $rollbackScriptPath = "$configPath\rollback_script.ps1"
    $rollbackScript | Out-File $rollbackScriptPath -Encoding UTF8 -Force
    
    # Créer la tâche planifiée
    try {
        # Supprimer ancienne tâche si existe
        Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:$false -EA SilentlyContinue
        
        # Créer nouvelle tâche qui se déclenche dans X minutes
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$rollbackScriptPath`""
        
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($rollbackTimeout)
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask "SYAGA-ATLAS-Rollback" -Action $action -Trigger $trigger -Principal $principal | Out-Null
        
        Write-Log "Tâche rollback créée - Déclenchement dans $rollbackTimeout min si pas annulée" "OK"
        return $true
        
    } catch {
        Write-Log "Impossible de créer tâche rollback: $_" "ERROR"
        return $false
    }
}

function Cancel-RollbackTask {
    Write-Log "Annulation tâche rollback - Update confirmé OK" "OK"
    
    try {
        Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:$false -EA SilentlyContinue
        
        # Supprimer le script de rollback
        $rollbackScriptPath = "$configPath\rollback_script.ps1"
        if (Test-Path $rollbackScriptPath) {
            Remove-Item $rollbackScriptPath -Force
        }
        
        Write-Log "Tâche rollback annulée avec succès" "OK"
        return $true
        
    } catch {
        Write-Log "Erreur annulation tâche rollback: $_" "WARNING"
        return $false
    }
}

function Check-RollbackFlag {
    # Vérifier si un rollback a eu lieu précédemment
    $rollbackInfoFile = "$configPath\rollback_info.json"
    
    if (Test-Path $rollbackInfoFile) {
        try {
            $rollbackInfo = Get-Content $rollbackInfoFile -Raw | ConvertFrom-Json
            Write-Log "!!! ROLLBACK DÉTECTÉ !!!" "CRITICAL"
            Write-Log "Date: $($rollbackInfo.RollbackDate)" "WARNING"
            Write-Log "Version échouée: $($rollbackInfo.FailedVersion)" "WARNING"
            Write-Log "Version restaurée: $($rollbackInfo.RestoredVersion)" "WARNING"
            Write-Log "Raison: $($rollbackInfo.Reason)" "WARNING"
            
            # Envoyer cette info à SharePoint
            Send-RollbackReport -RollbackInfo $rollbackInfo
            
            # Supprimer le flag
            Remove-Item $rollbackInfoFile -Force
            
            return $true
        } catch {
            Write-Log "Erreur lecture rollback info: $_" "ERROR"
        }
    }
    
    return $false
}

function Send-RollbackReport {
    param($RollbackInfo)
    
    Write-Log "Envoi rapport de rollback à SharePoint" "INFO"
    
    $token = Get-SharePointToken
    if (-not $token) { 
        Write-Log "Impossible d'envoyer rapport rollback - pas de token" "ERROR"
        return 
    }
    
    try {
        $hostname = $env:COMPUTERNAME
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        
        # Charger les logs d'échec si disponibles
        $failedLogs = ""
        $failedLogFile = "$configPath\failed_v$($RollbackInfo.FailedVersion).log"
        if (Test-Path $failedLogFile) {
            $failedLogs = Get-Content $failedLogFile -Tail 20 | Out-String
            Write-Log "Logs d'échec chargés depuis $failedLogFile" "OK"
        }
        
        # Créer entrée de rapport
        $report = @{
            __metadata = @{ type = "SP.Data.ATLASServersListItem" }
            Title = "ROLLBACK_$hostname"
            Hostname = "ROLLBACK_$hostname"
            State = "ROLLBACK_EXECUTED"
            AgentVersion = $RollbackInfo.RestoredVersion
            Role = "RollbackReport"
            VeeamStatus = "ROLLBACK: v$($RollbackInfo.FailedVersion) -> v$($RollbackInfo.RestoredVersion) | $($RollbackInfo.Reason)"
            LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose"
        }
        
        # Envoyer le rapport principal
        Invoke-RestMethod -Uri "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items" `
            -Method POST -Headers $headers -Body ($report | ConvertTo-Json -Depth 10) | Out-Null
        
        # Si on a des logs d'échec, les envoyer dans une entrée séparée
        if ($failedLogs) {
            $logsEntry = @{
                __metadata = @{ type = "SP.Data.ATLASServersListItem" }
                Title = "FAILED_LOGS_$hostname"
                Hostname = "FAILED_LOGS_$hostname"
                State = "ERROR_LOGS"
                AgentVersion = $RollbackInfo.FailedVersion
                Role = "ErrorLogs"
                VeeamStatus = $failedLogs.Substring(0, [Math]::Min($failedLogs.Length, 250))
                LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
            
            Invoke-RestMethod -Uri "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items" `
                -Method POST -Headers $headers -Body ($logsEntry | ConvertTo-Json -Depth 10) | Out-Null
        }
        
        Write-Log "Rapport de rollback envoyé avec succès" "OK"
        
    } catch {
        Write-Log "Erreur envoi rapport rollback: $_" "ERROR"
    }
}

function Get-SharePointToken {
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
        
        return $tokenResponse.access_token
    } catch {
        Write-Log "Erreur auth SharePoint: $_" "ERROR"
        return $null
    }
}

function Send-Heartbeat {
    Write-Log "Heartbeat v$version" "DEBUG"
    
    $token = Get-SharePointToken
    if (-not $token) { 
        Write-Log "Heartbeat impossible - pas de token" "ERROR"
        return $false
    }
    
    try {
        $hostname = $env:COMPUTERNAME
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        
        # Collecter métriques
        $os = Get-WmiObject Win32_OperatingSystem
        $cpu = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" 
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $memUsedPct = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 100 / $os.TotalVisibleMemorySize)
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        # Chercher entrée existante
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items?`$filter=Hostname eq '$hostname'"
        $existing = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET -EA SilentlyContinue
        
        $data = @{
            __metadata = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            State = if ($script:updateSuccess) { "UpdateSuccess" } else { "Online" }
            AgentVersion = $version
            LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            CPUPercent = [int]$cpu
            DiskSpaceGB = $diskFreeGB
            Role = "Server"
            MemoryUsedPercent = $memUsedPct
        }
        
        if ($existing.d.results.Count -gt 0) {
            # Update
            $itemId = $existing.d.results[0].Id
            $updateUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items($itemId)"
            $headers["IF-MATCH"] = "*"
            $headers["X-HTTP-Method"] = "MERGE"
            
            Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method POST `
                -Body ($data | ConvertTo-Json -Depth 10) | Out-Null
        } else {
            # Create
            $headers["Content-Type"] = "application/json;odata=verbose"
            Invoke-RestMethod -Uri "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items" `
                -Method POST -Headers $headers -Body ($data | ConvertTo-Json -Depth 10) | Out-Null
        }
        
        Write-Log "Heartbeat envoyé" "OK"
        return $true
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
        return $false
    }
}

function Check-Update {
    Write-Log "Check auto-update v5.5..." "UPDATE"
    
    $token = Get-SharePointToken
    if (-not $token) { 
        Write-Log "Check update impossible - pas de token" "ERROR"
        return 
    }
    
    try {
        $hostname = $env:COMPUTERNAME
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
        $items = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        
        foreach ($item in $items.d.results) {
            if ($item.Title -eq "UPDATE_COMMAND_$hostname" -or $item.Title -eq "UPDATE_ALL") {
                Write-Log ">>> UPDATE DETECTE: $($item.Title) <<<" "v55"
                
                $targetVersion = if ($item.AgentVersion) { $item.AgentVersion } else { "5.5" }
                Write-Log "Version cible: v$targetVersion" "UPDATE"
                
                # IMPORTANT: Créer tâche de rollback AVANT l'update
                $rollbackCreated = Create-RollbackTask -FromVersion $version -ToVersion $targetVersion
                
                if (-not $rollbackCreated) {
                    Write-Log "Impossible de créer tâche rollback - Update annulé" "ERROR"
                    return
                }
                
                # Sauvegarder version actuelle
                if (Test-Path "$configPath\agent.ps1") {
                    Copy-Item "$configPath\agent.ps1" "$configPath\agent.v$version.backup.ps1" -Force
                    $script:lastKnownGoodVersion = $version
                    Write-Log "Backup créé: agent.v$version.backup.ps1" "OK"
                }
                
                # Télécharger nouvelle version
                $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$targetVersion.ps1"
                Write-Log "Download: $newAgentUrl" "UPDATE"
                
                try {
                    $newAgent = Invoke-RestMethod -Uri $newAgentUrl -EA Stop
                    $newAgent | Out-File "$configPath\agent.ps1" -Encoding UTF8 -Force
                    
                    Write-Log "!!! AGENT MIS A JOUR VERS v$targetVersion !!!" "v55"
                    
                    # Supprimer la commande UPDATE
                    $deleteUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items($($item.Id))"
                    $headers["IF-MATCH"] = "*"
                    $headers["X-HTTP-Method"] = "DELETE"
                    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method POST
                    
                    Write-Log "Commande UPDATE supprimée" "OK"
                    Write-Log "L'agent va redémarrer avec v$targetVersion" "UPDATE"
                    Write-Log "La tâche de rollback est armée pour dans $rollbackTimeout minutes" "WARNING"
                    
                    # Logger succès de l'update
                    $updateLog = @{
                        __metadata = @{ type = "SP.Data.ATLASServersListItem" }
                        Title = "UPDATE_SUCCESS_$hostname"
                        Hostname = "UPDATE_SUCCESS_$hostname"
                        State = "UPDATE_APPLIED"
                        AgentVersion = $targetVersion
                        Role = "UpdateLog"
                        VeeamStatus = "UPDATE OK: v$version -> v$targetVersion @ $(Get-Date -Format 'HH:mm:ss')"
                        LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                    
                    $headers = @{
                        "Authorization" = "Bearer $token"
                        "Accept" = "application/json;odata=verbose"
                        "Content-Type" = "application/json;odata=verbose"
                    }
                    
                    Invoke-RestMethod -Uri "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items" `
                        -Method POST -Headers $headers -Body ($updateLog | ConvertTo-Json -Depth 10) | Out-Null
                    
                    # Fin de l'agent actuel
                    exit 0
                    
                } catch {
                    Write-Log "ERREUR UPDATE: $_" "ERROR"
                    Cancel-RollbackTask  # Annuler le rollback car on n'a pas fait l'update
                }
                
                break
            }
        }
    } catch {
        Write-Log "Erreur check update: $_" "ERROR"
    }
}

# MAIN EXECUTION
Write-Log "===== Agent ATLAS v$version DEMARRE =====" "v55"

# 1. Vérifier si on vient d'un rollback
$wasRolledBack = Check-RollbackFlag

# 2. Si pas de rollback, vérifier si on vient d'un update réussi
if (-not $wasRolledBack) {
    # Chercher une tâche de rollback active
    $rollbackTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -EA SilentlyContinue
    
    if ($rollbackTask) {
        Write-Log "Tâche de rollback détectée - Update récent" "INFO"
        
        # Tester que tout fonctionne
        $heartbeatOk = Send-Heartbeat
        
        if ($heartbeatOk) {
            Write-Log "✅ Agent v$version confirmé fonctionnel" "OK"
            $script:updateSuccess = $true
            
            # IMPORTANT: Annuler la tâche de rollback
            Cancel-RollbackTask
            
            # Logger le succès
            $token = Get-SharePointToken
            if ($token) {
                $hostname = $env:COMPUTERNAME
                $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
                
                $confirmLog = @{
                    __metadata = @{ type = "SP.Data.ATLASServersListItem" }
                    Title = "UPDATE_CONFIRMED_$hostname"
                    Hostname = "UPDATE_CONFIRMED_$hostname"
                    State = "UPDATE_STABLE"
                    AgentVersion = $version
                    Role = "UpdateConfirmation"
                    VeeamStatus = "v$version STABLE - Rollback annulé @ $(Get-Date -Format 'HH:mm:ss')"
                    LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                }
                
                $headers = @{
                    "Authorization" = "Bearer $token"
                    "Accept" = "application/json;odata=verbose"
                    "Content-Type" = "application/json;odata=verbose"
                }
                
                Invoke-RestMethod -Uri "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items" `
                    -Method POST -Headers $headers -Body ($confirmLog | ConvertTo-Json -Depth 10) -EA SilentlyContinue | Out-Null
            }
        } else {
            Write-Log "⚠️ Agent ne peut pas confirmer son état" "WARNING"
            Write-Log "La tâche de rollback reste active" "WARNING"
        }
    }
}

# 3. Charger config
$configFile = "$configPath\config.json"
if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        Write-Log "Config: $($config.ClientName) / $($config.ServerType)" "OK"
    } catch {
        Write-Log "Erreur lecture config: $_" "WARNING"
    }
}

# 4. Heartbeat normal
if (-not $script:updateSuccess) {
    Send-Heartbeat | Out-Null
}

# 5. Vérifier updates
Check-Update

# 6. Nettoyer vieux logs
$logFile = "$configPath\agent.log"
if (Test-Path $logFile) {
    $logSize = (Get-Item $logFile).Length / 1MB
    if ($logSize -gt 10) {
        $archive = "$configPath\agent.$(Get-Date -Format 'yyyyMMdd').log"
        Move-Item $logFile $archive -Force
        Get-ChildItem "$configPath\agent.*.log" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force
    }
}

Write-Log "===== Fin exécution v$version =====" "v55"