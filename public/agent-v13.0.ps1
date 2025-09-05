# ════════════════════════════════════════════════════════════════════
# ATLAS Agent v13.0 - COMPATIBLE AVEC UPDATER v13.0
# ════════════════════════════════════════════════════════════════════
# - Logs enrichis avec état updater
# - Monitoring de l'updater
# - Rapports détaillés
# ════════════════════════════════════════════════════════════════════

$script:Version = "13.5"
$hostname = $env:COMPUTERNAME
$atlasPath = "C:\SYAGA-ATLAS"

# Configuration SharePoint
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

# Buffer logs
$script:LogsBuffer = ""
$script:MaxBufferSize = 20000

# ════════════════════════════════════════════════════════════════════
# FONCTION LOG
# ════════════════════════════════════════════════════════════════════
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
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        "DEBUG" { Write-Host $logEntry -ForegroundColor DarkGray }
        default { Write-Host $logEntry }
    }
    
    # Écrire dans le fichier log
    $logFile = "$atlasPath\atlas_log.txt"
    try {
        Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    } catch {
        # Silencieux si impossible d'écrire
    }
}

# ════════════════════════════════════════════════════════════════════
# FONCTION POUR LIRE L'ÉTAT DE L'UPDATER
# ════════════════════════════════════════════════════════════════════
function Get-UpdaterStatus {
    $updaterInfo = @{
        Version = "Unknown"
        LastCheck = "Never"
        LastUpdate = "Never"
        Status = "Unknown"
        LastError = $null
        LogsAvailable = $false
        StateFileExists = $false
    }
    
    try {
        # Lire le fichier d'état de l'updater v13.0
        $statePath = "$atlasPath\updater-state.json"
        if (Test-Path $statePath) {
            $updaterInfo.StateFileExists = $true
            $state = Get-Content $statePath -Raw | ConvertFrom-Json
            
            $updaterInfo.Version = if ($state.CurrentVersion) { $state.CurrentVersion } else { "Unknown" }
            $updaterInfo.LastCheck = if ($state.LastCheck) { $state.LastCheck } else { "Never" }
            $updaterInfo.LastUpdate = if ($state.LastUpdate) { $state.LastUpdate } else { "Never" }
            $updaterInfo.Status = if ($state.Status) { $state.Status } else { "Unknown" }
            $updaterInfo.LastError = $state.LastError
            
            # Calculer temps depuis dernière vérification
            if ($state.LastCheck) {
                $lastCheckTime = [DateTime]::Parse($state.LastCheck)
                $timeSince = (Get-Date) - $lastCheckTime
                $updaterInfo.MinutesSinceCheck = [int]$timeSince.TotalMinutes
            }
        }
        
        # Vérifier les logs de l'updater
        $logsPath = "$atlasPath\logs"
        if (Test-Path $logsPath) {
            $todayLog = "$logsPath\updater_$(Get-Date -Format 'yyyyMMdd').log"
            if (Test-Path $todayLog) {
                $updaterInfo.LogsAvailable = $true
                
                # Lire les dernières lignes du log
                $lastLines = Get-Content $todayLog -Tail 5 -ErrorAction SilentlyContinue
                $updaterInfo.RecentLogs = $lastLines -join " | "
            }
        }
        
        # Vérifier la tâche planifiée
        $updaterTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
        if ($updaterTask) {
            $updaterInfo.TaskState = $updaterTask.State
            
            $taskInfo = Get-ScheduledTaskInfo -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
            if ($taskInfo) {
                $updaterInfo.TaskLastRun = $taskInfo.LastRunTime.ToString("yyyy-MM-dd HH:mm:ss")
                $updaterInfo.TaskNextRun = $taskInfo.NextRunTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
        
    } catch {
        Write-Log "Erreur lecture état updater: $_" "WARNING"
    }
    
    return $updaterInfo
}

# ════════════════════════════════════════════════════════════════════
# FONCTION HEARTBEAT AVEC MONITORING UPDATER
# ════════════════════════════════════════════════════════════════════
function Send-Heartbeat {
    try {
        Write-Log "Préparation heartbeat..." "DEBUG"
        
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
        
        # Collecter les métriques système
        Write-Log "Collecte métriques système..." "DEBUG"
        
        $cpu = Get-WmiObject -Class Win32_Processor
        $cpuUsage = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average)
        
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $memTotal = $os.TotalVisibleMemorySize
        $memFree = $os.FreePhysicalMemory
        $memUsage = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)
        $memUsedMB = [math]::Round(($memTotal - $memFree) / 1024, 1)
        $memTotalMB = [math]::Round($memTotal / 1024, 1)
        
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $diskTotalGB = [math]::Round($disk.Size / 1GB, 1)
        $diskUsedPercent = [math]::Round((($diskTotalGB - $diskFreeGB) / $diskTotalGB) * 100, 1)
        
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        Write-Log "CPU=$cpuUsage% MEM=$memUsage% ($memUsedMB/$memTotalMB MB) DISK=$diskFreeGB/$diskTotalGB GB ($diskUsedPercent% used)" "INFO"
        
        # Obtenir l'état de l'updater
        Write-Log "Vérification état updater..." "DEBUG"
        $updaterStatus = Get-UpdaterStatus
        
        # Déterminer le statut de l'auto-update
        $autoUpdateStatus = "Unknown"
        if ($updaterStatus.StateFileExists) {
            if ($updaterStatus.Status -eq "Running") {
                $autoUpdateStatus = "Active"
            } elseif ($updaterStatus.Status -eq "Error") {
                $autoUpdateStatus = "Error"
            } elseif ($updaterStatus.MinutesSinceCheck -lt 5) {
                $autoUpdateStatus = "OK"
            } elseif ($updaterStatus.MinutesSinceCheck -lt 60) {
                $autoUpdateStatus = "Delayed"
            } else {
                $autoUpdateStatus = "Inactive"
            }
        }
        
        Write-Log "Updater: $autoUpdateStatus (dernière vérif: $($updaterStatus.LastCheck))" "INFO"
        
        # Créer le rapport enrichi
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logHeader = @"
════════════════════════════════════════════════════════════════════
ATLAS v$($script:Version) - MONITORING REPORT
════════════════════════════════════════════════════════════════════
Hostname: $hostname ($ip)
Time: $currentTime

AGENT STATUS:
  Version: $($script:Version)
  Status: Active
  
UPDATER STATUS:
  Version: $($updaterStatus.Version)
  Status: $($updaterStatus.Status)
  Last Check: $($updaterStatus.LastCheck)
  Last Update: $($updaterStatus.LastUpdate)
  Auto-Update: $autoUpdateStatus
  $(if ($updaterStatus.LastError) { "Last Error: $($updaterStatus.LastError)" })
  
SYSTEM METRICS:
  CPU: $cpuUsage%
  Memory: $memUsage% ($memUsedMB MB / $memTotalMB MB)
  Disk C:\: $diskFreeGB GB free / $diskTotalGB GB total ($diskUsedPercent% used)
  
SCHEDULED TASKS:
  Agent Task: $((Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue).State)
  Updater Task: $(if ($updaterStatus.TaskState) { $updaterStatus.TaskState } else { "Not found" })

════════════════════════════════════════════════════════════════════
RECENT ACTIVITY:
════════════════════════════════════════════════════════════════════
"@
        
        # Ajouter les logs
        $enrichedLogs = $logHeader + "`r`n" + $script:LogsBuffer
        
        # Créer le champ Notes avec infos de tracking
        $notesData = "Agent:v$($script:Version)|Updater:$($updaterStatus.Status)|AutoUpdate:$autoUpdateStatus|LastCheck:$($updaterStatus.LastCheck)"
        
        # Préparer les données pour SharePoint
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
            Notes = $notesData
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Envoyer à SharePoint
        Write-Log "Envoi heartbeat à SharePoint..." "DEBUG"
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Heartbeat envoyé avec succès" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════
Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS AGENT v$($script:Version) DÉMARRAGE" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

# Vérifier l'environnement
if (!(Test-Path $atlasPath)) {
    New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null
    Write-Log "Dossier ATLAS créé: $atlasPath" "INFO"
}

# Vérifier l'état de l'updater
$updaterStatus = Get-UpdaterStatus
if ($updaterStatus.StateFileExists) {
    Write-Log "Updater v13.0 détecté - État: $($updaterStatus.Status)" "INFO"
} else {
    Write-Log "Updater v13.0 pas encore configuré" "WARNING"
}

# Envoyer le heartbeat
Send-Heartbeat

Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS AGENT v$($script:Version) TERMINÉ" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

exit 0