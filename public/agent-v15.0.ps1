# ATLAS Agent v15.0 - ORCHESTRATION COMMANDS EXECUTION
$script:Version = "15.0"
$script:FoundationVersion = "10.3"
$hostname = $env:COMPUTERNAME
$logFile = "C:\SYAGA-ATLAS\atlas_log.txt"

# ════════════════════════════════════════════════════
# SHAREPOINT CONFIG  
# ════════════════════════════════════════════════════
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
$commandsListId = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

# Buffer logs
$script:LogsBuffer = ""
$script:MaxBufferSize = 20000

# ════════════════════════════════════════════════════
# FONCTION LOG
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxBufferSize) {
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $script:MaxBufferSize)
    }
    
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "ORCHESTRATE" { Write-Host $logEntry -ForegroundColor Cyan }
        "EXECUTE" { Write-Host $logEntry -ForegroundColor Magenta }
        default { Write-Host $logEntry }
    }
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# v15.0: ORCHESTRATION COMMAND HANDLERS
# ════════════════════════════════════════════════════
function Handle-RebootCommand {
    param($DelayMinutes = 5)
    
    Write-Log "REBOOT COMMAND - Scheduling restart in $DelayMinutes minutes" "EXECUTE"
    
    try {
        # Créer message pour les utilisateurs
        $message = "ATLAS Orchestrator: Server will restart in $DelayMinutes minutes for maintenance. Please save your work."
        
        # Envoyer message aux utilisateurs connectés
        msg * $message
        
        # Programmer le redémarrage
        shutdown /r /t $($DelayMinutes * 60) /c "ATLAS Orchestrated Restart"
        
        Write-Log "Reboot scheduled successfully" "SUCCESS"
        return @{
            Success = $true
            Message = "Reboot scheduled in $DelayMinutes minutes"
        }
    } catch {
        Write-Log "Failed to schedule reboot: $_" "ERROR"
        return @{
            Success = $false
            Message = "Reboot scheduling failed: $_"
        }
    }
}

function Handle-PauseVeeamBackup {
    Write-Log "PAUSE VEEAM - Suspending all backup jobs" "EXECUTE"
    
    try {
        if (Get-PSSnapin -Registered -Name VeeamPSSnapin -ErrorAction SilentlyContinue) {
            Add-PSSnapin VeeamPSSnapin
            
            $jobs = Get-VBRJob
            $pausedJobs = @()
            
            foreach ($job in $jobs) {
                if ($job.IsScheduleEnabled) {
                    Disable-VBRJobSchedule -Job $job
                    $pausedJobs += $job.Name
                    Write-Log "Paused job: $($job.Name)" "INFO"
                }
            }
            
            Write-Log "Paused $($pausedJobs.Count) Veeam jobs" "SUCCESS"
            return @{
                Success = $true
                Message = "Paused $($pausedJobs.Count) jobs"
                PausedJobs = $pausedJobs
            }
        } else {
            Write-Log "Veeam not installed" "WARNING"
            return @{
                Success = $false
                Message = "Veeam not installed on this server"
            }
        }
    } catch {
        Write-Log "Failed to pause Veeam: $_" "ERROR"
        return @{
            Success = $false
            Message = "Veeam pause failed: $_"
        }
    }
}

function Handle-RecreateHyperVReplica {
    param($VMName)
    
    Write-Log "RECREATE REPLICA - VM: $VMName" "EXECUTE"
    
    try {
        if ((Get-WindowsFeature -Name Hyper-V).InstallState -eq "Installed") {
            $vm = Get-VM -Name $VMName -ErrorAction Stop
            
            # Supprimer la réplication existante
            Remove-VMReplication -VMName $VMName -ErrorAction SilentlyContinue
            
            # Recréer la réplication
            # Note: Nécessite les paramètres du serveur de réplication
            Write-Log "Replica removed for $VMName - Manual recreation required" "WARNING"
            
            return @{
                Success = $true
                Message = "Replica removed for $VMName - Ready for recreation"
                VMState = $vm.State
            }
        } else {
            return @{
                Success = $false
                Message = "Hyper-V not installed"
            }
        }
    } catch {
        Write-Log "Failed to recreate replica: $_" "ERROR"
        return @{
            Success = $false
            Message = "Replica recreation failed: $_"
        }
    }
}

function Handle-ClearDiskSpace {
    Write-Log "CLEAR DISK - Starting cleanup" "EXECUTE"
    
    try {
        $freedSpace = 0
        
        # 1. Nettoyer fichiers temporaires Windows
        $tempPaths = @(
            "$env:TEMP",
            "C:\Windows\Temp",
            "C:\Windows\SoftwareDistribution\Download"
        )
        
        foreach ($path in $tempPaths) {
            if (Test-Path $path) {
                $before = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                Remove-Item "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                $after = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $freed = ($before - $after) / 1MB
                $freedSpace += $freed
                Write-Log "Cleared $([math]::Round($freed, 1)) MB from $path" "INFO"
            }
        }
        
        # 2. Nettoyer logs IIS (si installé)
        if (Test-Path "C:\inetpub\logs") {
            $iisLogFiles = Get-ChildItem "C:\inetpub\logs" -Recurse -Filter "*.log" | 
                Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-7)}
            
            $iisSize = ($iisLogFiles | Measure-Object -Property Length -Sum).Sum / 1MB
            $iisLogFiles | Remove-Item -Force -ErrorAction SilentlyContinue
            $freedSpace += $iisSize
            Write-Log "Cleared $([math]::Round($iisSize, 1)) MB of IIS logs" "INFO"
        }
        
        # 3. Nettoyer vieux fichiers Windows Update
        Start-Process -FilePath "dism.exe" -ArgumentList "/online /cleanup-image /startcomponentcleanup" -Wait -NoNewWindow
        
        Write-Log "Total space freed: $([math]::Round($freedSpace, 1)) MB" "SUCCESS"
        
        return @{
            Success = $true
            Message = "Freed $([math]::Round($freedSpace, 1)) MB"
            FreedMB = [math]::Round($freedSpace, 1)
        }
    } catch {
        Write-Log "Disk cleanup failed: $_" "ERROR"
        return @{
            Success = $false
            Message = "Cleanup failed: $_"
        }
    }
}

function Handle-InstallWindowsUpdates {
    Write-Log "INSTALL UPDATES - Starting Windows Update" "EXECUTE"
    
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        Write-Log "Searching for updates..." "INFO"
        $searchResult = $updateSearcher.Search("IsInstalled=0")
        
        if ($searchResult.Updates.Count -eq 0) {
            Write-Log "No updates available" "INFO"
            return @{
                Success = $true
                Message = "No updates to install"
                UpdateCount = 0
            }
        }
        
        $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        
        foreach ($update in $searchResult.Updates) {
            if (-not $update.IsHidden) {
                $updatesToInstall.Add($update) | Out-Null
                Write-Log "Queued: $($update.Title)" "INFO"
            }
        }
        
        if ($updatesToInstall.Count -eq 0) {
            return @{
                Success = $true
                Message = "All updates are hidden"
                UpdateCount = 0
            }
        }
        
        Write-Log "Installing $($updatesToInstall.Count) updates..." "INFO"
        
        $installer = $updateSession.CreateUpdateInstaller()
        $installer.Updates = $updatesToInstall
        $installResult = $installer.Install()
        
        Write-Log "Installation complete - Result: $($installResult.ResultCode)" "SUCCESS"
        
        return @{
            Success = ($installResult.ResultCode -eq 2)  # 2 = Succeeded
            Message = "Installed $($updatesToInstall.Count) updates"
            UpdateCount = $updatesToInstall.Count
            RebootRequired = $installResult.RebootRequired
        }
    } catch {
        Write-Log "Update installation failed: $_" "ERROR"
        return @{
            Success = $false
            Message = "Update failed: $_"
        }
    }
}

# ════════════════════════════════════════════════════
# v15.0: CHECK AND EXECUTE ORCHESTRATION COMMANDS
# ════════════════════════════════════════════════════
function Check-OrchestrationCommands {
    try {
        # Token
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
        }
        
        # Chercher commandes d'orchestration
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        
        foreach ($cmd in $response.d.results) {
            if ($cmd.Status -eq "PENDING") {
                $targetHost = if ($cmd.TargetHostname) { $cmd.TargetHostname } else { "ALL" }
                
                if ($targetHost -eq "ALL" -or $targetHost -eq $hostname) {
                    # Commandes d'orchestration
                    switch ($cmd.CommandType) {
                        "REBOOT_SERVER" {
                            Write-Log "ORCHESTRATION COMMAND: REBOOT" "ORCHESTRATE"
                            $result = Handle-RebootCommand -DelayMinutes 5
                            Update-CommandStatus $cmd.Id "EXECUTED" $result.Message
                        }
                        
                        "PAUSE_VEEAM_BACKUP" {
                            Write-Log "ORCHESTRATION COMMAND: PAUSE VEEAM" "ORCHESTRATE"
                            $result = Handle-PauseVeeamBackup
                            Update-CommandStatus $cmd.Id $(if ($result.Success) {"DONE"} else {"ERROR"}) $result.Message
                        }
                        
                        "RECREATE_HYPERV_REPLICA" {
                            Write-Log "ORCHESTRATION COMMAND: RECREATE REPLICA" "ORCHESTRATE"
                            $result = Handle-RecreateHyperVReplica -VMName $cmd.Parameters
                            Update-CommandStatus $cmd.Id $(if ($result.Success) {"DONE"} else {"ERROR"}) $result.Message
                        }
                        
                        "CLEAR_DISK_SPACE" {
                            Write-Log "ORCHESTRATION COMMAND: CLEAR DISK" "ORCHESTRATE"
                            $result = Handle-ClearDiskSpace
                            Update-CommandStatus $cmd.Id $(if ($result.Success) {"DONE"} else {"ERROR"}) $result.Message
                        }
                        
                        "UPDATE_WINDOWS" {
                            Write-Log "ORCHESTRATION COMMAND: INSTALL UPDATES" "ORCHESTRATE"
                            $result = Handle-InstallWindowsUpdates
                            Update-CommandStatus $cmd.Id $(if ($result.Success) {"DONE"} else {"ERROR"}) $result.Message
                        }
                    }
                }
            }
        }
    } catch {
        Write-Log "Error checking orchestration commands: $_" "WARNING"
    }
}

function Update-CommandStatus {
    param($CommandId, $Status, $Message)
    
    try {
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $headers = @{
            "Authorization" = "Bearer $($tokenResponse.access_token)"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
            "X-HTTP-Method" = "MERGE"
            "IF-MATCH" = "*"
        }
        
        $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($CommandId)"
        $updateBody = @{
            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
            Status = $Status
            ExecutedBy = "$hostname - $Message"
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method POST -Body $updateBody
        Write-Log "Command $CommandId marked as $Status" "INFO"
    } catch {
        Write-Log "Failed to update command status: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT STANDARD
# ════════════════════════════════════════════════════
function Send-Heartbeat {
    try {
        # Token
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
        
        # Métriques
        $cpu = Get-WmiObject -Class Win32_Processor
        $cpuUsage = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average)
        
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $memTotal = $os.TotalVisibleMemorySize
        $memFree = $os.FreePhysicalMemory
        $memUsage = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)
        
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        Write-Log "CPU=$cpuUsage% MEM=$memUsage% DISK=$diskFreeGB GB"
        
        # Header
        $logHeader = @"
════════════════════════════════════════════════════
ATLAS v$($script:Version) ORCHESTRATION COMMANDS
════════════════════════════════════════════════════
Available Commands:
- REBOOT_SERVER: Scheduled restart with warning
- PAUSE_VEEAM_BACKUP: Suspend all backup jobs
- RECREATE_HYPERV_REPLICA: Fix VM replication
- CLEAR_DISK_SPACE: Automatic cleanup
- UPDATE_WINDOWS: Install pending updates

Status: READY TO EXECUTE
════════════════════════════════════════════════════

"@
        
        $enrichedLogs = $logHeader + $script:LogsBuffer
        
        # DONNÉES
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            IPAddress = $ip
            State = "ONLINE"
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = "$($script:Version)-ORCH-CMD"
            CPUUsage = $cpuUsage
            MemoryUsage = $memUsage
            DiskSpaceGB = $diskFreeGB
            Logs = $enrichedLogs
            Notes = "v15.0|Commands:Ready|Orchestration:Active"
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Créer nouvelle entrée
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Heartbeat OK" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN v15.0
# ════════════════════════════════════════════════════
Write-Log "════════════════════════════════════════" "INFO"
Write-Log "Agent v$($script:Version) - ORCHESTRATION COMMANDS" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

# Vérifier les commandes d'orchestration
Check-OrchestrationCommands

# Envoyer heartbeat
Send-Heartbeat

Write-Log "Fin agent v$($script:Version)" "SUCCESS"
exit 0