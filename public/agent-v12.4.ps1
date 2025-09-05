# ATLAS Agent v12.4 - TRACKING AGENT + UPDATER
$script:Version = "12.4"
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

# Buffer logs
$script:LogsBuffer = ""
$script:MaxBufferSize = 8000

# ════════════════════════════════════════════════════
# FONCTION LOG
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Buffer
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxBufferSize) {
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $script:MaxBufferSize)
    }
    
    # Afficher
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# FONCTION POUR OBTENIR L'ACTIVITÉ DE L'UPDATER
# ════════════════════════════════════════════════════
function Get-UpdaterActivity {
    $updaterInfo = @{
        LastRun = "Never"
        Version = "Unknown"
        Status = "Unknown"
    }
    
    try {
        # Vérifier le log de l'updater
        $updaterLogPath = "C:\SYAGA-ATLAS\updater_log.txt"
        if (Test-Path $updaterLogPath) {
            # Obtenir la dernière modification du fichier
            $lastModified = (Get-Item $updaterLogPath).LastWriteTime
            $updaterInfo.LastRun = $lastModified.ToString("yyyy-MM-dd HH:mm:ss")
            
            # Lire les dernières lignes pour avoir la version
            $lastLines = Get-Content $updaterLogPath -Tail 20
            foreach ($line in $lastLines) {
                if ($line -match "UPDATER v([\d\.]+)") {
                    $updaterInfo.Version = $matches[1]
                }
            }
            
            # Vérifier si actif (modifié dans les 2 dernières minutes)
            $timeDiff = (Get-Date) - $lastModified
            if ($timeDiff.TotalMinutes -lt 2) {
                $updaterInfo.Status = "ACTIVE"
            } elseif ($timeDiff.TotalMinutes -lt 10) {
                $updaterInfo.Status = "RECENT"
            } else {
                $updaterInfo.Status = "INACTIVE"
            }
        }
        
        # Vérifier la tâche planifiée
        $task = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
        if ($task) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
            if ($taskInfo) {
                $updaterInfo.TaskLastRun = $taskInfo.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss")
                $updaterInfo.TaskNextRun = $taskInfo.NextRunTime.ToString("yyyy-MM-dd HH:mm:ss")
                $updaterInfo.TaskState = $task.State
            }
        }
        
    } catch {
        Write-Log "Erreur lecture updater: $_" "WARNING"
    }
    
    return $updaterInfo
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT AVEC TRACKING
# ════════════════════════════════════════════════════
function Send-HeartbeatWithTracking {
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
        
        # Métriques système
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
        
        # Obtenir info updater
        $updaterInfo = Get-UpdaterActivity
        
        # Créer header enrichi pour les logs
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logHeader = @"
=== ATLAS v$($script:Version) STATUS ===
Agent Last Run: $currentTime
Agent Version: $($script:Version)
Updater Last Run: $($updaterInfo.LastRun)
Updater Version: $($updaterInfo.Version)
Updater Status: $($updaterInfo.Status)
System: CPU=$cpuUsage% MEM=$memUsage% DISK=$diskFreeGB GB
================================
"@
        
        # Ajouter les logs
        $enrichedLogs = $logHeader + "`r`n" + $script:LogsBuffer
        
        # Créer champs séparés pour le tracking
        $agentLastRun = $currentTime
        $updaterLastRun = $updaterInfo.LastRun
        
        # DONNÉES avec tracking séparé
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            IPAddress = $ip
            State = "ONLINE"
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = $script:Version
            CPUUsage = $cpuUsage
            MemoryUsage = $memUsage
            DiskSpaceGB = $diskFreeGB
            Logs = $enrichedLogs
            # v12.4: Nouveaux champs pour tracking
            Notes = "Agent:$agentLastRun|Updater:$updaterLastRun|UpdaterStatus:$($updaterInfo.Status)"
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Créer nouvelle entrée
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Heartbeat OK (Agent:$currentTime, Updater:$($updaterInfo.LastRun))" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════
Write-Log "Agent v$($script:Version) - TRACKING" "SUCCESS"
Write-Log "Collecte info updater..."

$updaterInfo = Get-UpdaterActivity
Write-Log "Updater v$($updaterInfo.Version) - $($updaterInfo.Status)"
Write-Log "Updater last: $($updaterInfo.LastRun)"

Send-HeartbeatWithTracking

Write-Log "Fin agent v$($script:Version)"
exit 0