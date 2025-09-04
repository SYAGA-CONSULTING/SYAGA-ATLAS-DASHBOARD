# ATLAS Agent v5.9 - Version Complète avec Auto-Update & Rollback
$version = "5.9"
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
function Create-RollbackTask {
    param([string]$FromVersion, [string]$ToVersion)
    
    Write-Log "[ROLLBACK] Création tâche rollback (timeout: $rollbackTimeout min)" "ROLLBACK"
    
    $rollbackScript = @"
# ROLLBACK AUTOMATIQUE ATLAS
`$configPath = 'C:\SYAGA-ATLAS'
`$logFile = "`$configPath\rollback.log"

function Log {
    param(`$msg)
    "`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - `$msg" | Out-File `$logFile -Append -Encoding UTF8
}

Log "=== ROLLBACK AUTOMATIQUE DÉCLENCHÉ ==="
Log "Version actuelle: $ToVersion"
Log "Rollback vers: $FromVersion"

# Sauvegarder logs d'échec
if (Test-Path "`$configPath\agent.log") {
    Copy-Item "`$configPath\agent.log" "`$configPath\failed_v$ToVersion.log" -Force
    Log "Logs d'échec sauvegardés"
}

# Télécharger version stable
try {
    `$url = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$FromVersion.ps1"
    Log "Téléchargement depuis `$url"
    `$agent = Invoke-RestMethod -Uri `$url -EA Stop
    `$agent | Out-File "`$configPath\agent.ps1" -Encoding UTF8 -Force
    Log "ROLLBACK RÉUSSI - Agent v$FromVersion restauré"
    
    # Créer flag pour notification
    @{
        RollbackDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        FailedVersion = "$ToVersion"
        RestoredVersion = "$FromVersion"
        Reason = "Timeout $rollbackTimeout min - Pas de confirmation"
    } | ConvertTo-Json | Out-File "`$configPath\rollback_info.json" -Force
    
} catch {
    Log "ERREUR ROLLBACK: `$_"
}

# Supprimer cette tâche
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:`$false -EA SilentlyContinue
Log "=== FIN ROLLBACK ==="
"@
    
    $rollbackScriptPath = "$configPath\rollback_script.ps1"
    $rollbackScript | Out-File $rollbackScriptPath -Encoding UTF8 -Force
    
    try {
        # Supprimer ancienne tâche si existe
        Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:$false -EA SilentlyContinue
        
        # Créer nouvelle tâche
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$rollbackScriptPath`""
        
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($rollbackTimeout)
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask "SYAGA-ATLAS-Rollback" -Action $action -Trigger $trigger -Principal $principal | Out-Null
        
        Write-Log "[ROLLBACK] Tâche créée avec succès - Déclenchement dans $rollbackTimeout min" "OK"
        return $true
        
    } catch {
        Write-Log "[ROLLBACK] ERREUR création tâche: $_" "ERROR"
        return $false
    }
}

function Cancel-RollbackTask {
    Write-Log "[ROLLBACK] Annulation tâche - Update confirmé stable" "OK"
    try {
        Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Rollback" -Confirm:$false -EA SilentlyContinue
        Remove-Item "$configPath\rollback_script.ps1" -Force -EA SilentlyContinue
        Write-Log "[ROLLBACK] Tâche et script supprimés" "OK"
        return $true
    } catch {
        Write-Log "[ROLLBACK] Erreur annulation: $_" "WARNING"
        return $false
    }
}

function Check-RollbackInfo {
    $rollbackInfoFile = "$configPath\rollback_info.json"
    if (Test-Path $rollbackInfoFile) {
        try {
            $info = Get-Content $rollbackInfoFile -Raw | ConvertFrom-Json
            Write-Log "!!! ROLLBACK PRÉCÉDENT DÉTECTÉ !!!" "WARNING"
            Write-Log "Version échouée: $($info.FailedVersion) → Restaurée: $($info.RestoredVersion)" "WARNING"
            Write-Log "Date: $($info.RollbackDate) - Raison: $($info.Reason)" "WARNING"
            
            # Envoyer rapport à SharePoint
            Send-RollbackReport -Info $info
            
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
    param($Info)
    Write-Log "Envoi rapport de rollback à SharePoint..." "INFO"
    # Le rapport sera envoyé dans Send-Heartbeat avec les autres métriques
    $script:rollbackReport = $Info
}

Write-Log "===== Agent ATLAS v$version DEMARRE =====" "OK"

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
                
                # IMPORTANT: Créer tâche rollback AVANT update
                $rollbackCreated = Create-RollbackTask -FromVersion $version -ToVersion $targetVersion
                if (-not $rollbackCreated) {
                    Write-Log "Impossible de créer tâche rollback - Update annulé" "ERROR"
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
                    
                    # Supprimer la commande
                    $deleteUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items($($item.Id))"
                    $headers["IF-MATCH"] = "*"
                    $headers["X-HTTP-Method"] = "DELETE"
                    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method POST
                    Write-Log "Commande UPDATE supprimée" "OK"
                    
                    Write-Log "Redémarrage avec v$targetVersion dans quelques secondes..." "UPDATE"
                    Write-Log "[ROLLBACK] Tâche armée pour dans $rollbackTimeout minutes" "ROLLBACK"
                    
                    # Arrêt pour redémarrage
                    exit 0
                    
                } catch {
                    Write-Log "ERREUR UPDATE: $_" "ERROR"
                    Cancel-RollbackTask  # Annuler car pas d'update fait
                }
                
                break
            }
        }
    } catch {
        Write-Log "Erreur check update: $_" "ERROR"
    }
}

# FONCTION HEARTBEAT
function Send-Heartbeat {
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
        
        # Collecter métriques
        $hostname = $env:COMPUTERNAME
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        if ($null -eq $cpu) { $cpu = 0 }
        
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $diskUsedPct = [math]::Round((($disk.Size - $disk.FreeSpace) * 100 / $disk.Size), 1)
        
        $memUsedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        $memTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $memUsedPct = [math]::Round(($memUsedGB * 100 / $memTotalGB), 1)
        
        $uptimeDays = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
        
        # Vérifier Veeam
        $veeamStatus = "N/A"
        $veeamService = Get-Service -Name "VeeamBackupSvc" -EA SilentlyContinue
        if ($veeamService) {
            $veeamStatus = $veeamService.Status
        }
        
        # Status text avec rapport de rollback si applicable
        $statusText = "v$version | Up:${uptimeDays}d | $veeamStatus"
        if ($script:rollbackReport) {
            $statusText = "ROLLBACK: $($script:rollbackReport.FailedVersion)→$($script:rollbackReport.RestoredVersion) | $statusText"
        }
        
        # Préparer données
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        $data = @{
            __metadata = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            State = "Online"
            AgentVersion = $version
            LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            CPUPercent = [int]$cpu
            DiskSpaceGB = $diskFreeGB
            VeeamStatus = $statusText
            Role = "Server"
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
        
        # Logger succès dans SharePoint
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
            $hostname = $env:COMPUTERNAME
            $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
            
            $logData = @{
                __metadata = @{ type = "SP.Data.ATLASServersListItem" }
                Title = "UPDATE_CONFIRMED_$hostname"
                Hostname = "UPDATE_CONFIRMED_$hostname"
                State = "UPDATE_STABLE"
                AgentVersion = $version
                Role = "UpdateLog"
                VeeamStatus = "v$version STABLE - Rollback annulé @ $(Get-Date -Format 'HH:mm:ss')"
                LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
            
            $headers = @{
                "Authorization" = "Bearer $token"
                "Accept" = "application/json;odata=verbose"
                "Content-Type" = "application/json;odata=verbose"
            }
            
            Invoke-RestMethod -Uri "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items" `
                -Method POST -Headers $headers -Body ($logData | ConvertTo-Json -Depth 10) -EA SilentlyContinue
                
        } catch {
            # Pas grave si le log échoue
        }
    } else {
        Write-Log "⚠️ Heartbeat échoué - Tâche rollback reste active" "WARNING"
    }
} else {
    # Heartbeat normal
    Send-Heartbeat | Out-Null
}

# Vérifier updates
Check-Update

Write-Log "===== Agent v$version TERMINE =====" "OK"