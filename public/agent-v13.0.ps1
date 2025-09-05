# ATLAS Agent v13.0 - ROLLBACK AUTOMATIQUE < 30 SECONDES
$script:Version = "13.0"
$hostname = $env:COMPUTERNAME
$logFile = "C:\SYAGA-ATLAS\atlas_log.txt"
$jsonLogFile = "C:\SYAGA-ATLAS\atlas_log.json"

# ════════════════════════════════════════════════════
# v13.0 : CONFIGURATION ROLLBACK
# ════════════════════════════════════════════════════
$script:RollbackConfig = @{
    PreviousVersion = "12.0"  # Version de secours
    MaxErrorCount = 3         # Erreurs max avant rollback
    HealthcheckTimeout = 20   # Secondes pour validation
    RollbackHistory = @()     # Historique des rollbacks
}

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

# ════════════════════════════════════════════════════
# v12.0 : SYSTÈME DE LOGS AVANCÉ (conservé)
# ════════════════════════════════════════════════════
$script:LogsBuffer = @()
$script:MaxBufferSize = 1000
$script:LogCounters = @{
    INFO = 0
    WARNING = 0
    ERROR = 0
    SUCCESS = 0
    DEBUG = 0
    CRITICAL = 0  # v13.0: Nouveau niveau pour rollback
}

# ════════════════════════════════════════════════════
# FONCTION LOG v13.0 - AVEC DÉTECTION CRITIQUE
# ════════════════════════════════════════════════════
function Write-Log {
    param(
        $Message, 
        $Level = "INFO",
        $Component = "MAIN",
        $ErrorDetails = $null
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $timestampShort = Get-Date -Format "HH:mm:ss"
    
    # Log texte classique
    $logEntry = "[$timestampShort] [$Level] $Message"
    
    # Log JSON structuré
    $jsonLog = @{
        Timestamp = $timestamp
        Level = $Level
        Component = $Component
        Message = $Message
        Hostname = $hostname
        Version = $script:Version
    }
    
    if ($ErrorDetails) {
        $jsonLog.ErrorDetails = $ErrorDetails
    }
    
    # Buffer circulaire
    $script:LogsBuffer += @{
        Text = $logEntry
        Json = $jsonLog
    }
    
    # Limiter la taille du buffer
    if ($script:LogsBuffer.Count -gt $script:MaxBufferSize) {
        $script:LogsBuffer = $script:LogsBuffer[-$script:MaxBufferSize..-1]
    }
    
    # Incrémenter compteurs
    $script:LogCounters[$Level]++
    
    # v13.0: Détecter seuil critique pour rollback
    if ($Level -eq "ERROR" -and $script:LogCounters.ERROR -ge $script:RollbackConfig.MaxErrorCount) {
        Write-Host "[ROLLBACK] Seuil d'erreurs atteint ($($script:LogCounters.ERROR))" -ForegroundColor Magenta
        Invoke-AutoRollback -Reason "TooManyErrors"
    }
    
    # Afficher
    switch($Level) {
        "CRITICAL" { Write-Host $logEntry -ForegroundColor Magenta }
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        default { Write-Host $logEntry }
    }
    
    # Écrire dans les fichiers
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    $jsonLog | ConvertTo-Json -Compress | Add-Content -Path $jsonLogFile -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# v13.0: FONCTION HEALTHCHECK
# ════════════════════════════════════════════════════
function Test-AgentHealth {
    Write-Log "Healthcheck v13.0" "DEBUG" "HEALTH"
    
    $healthStatus = @{
        SharePoint = $false
        DiskSpace = $false
        Memory = $false
        Critical = $false
    }
    
    try {
        # Test SharePoint
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -TimeoutSec 10
        
        if ($tokenResponse.access_token) {
            $healthStatus.SharePoint = $true
            Write-Log "SharePoint: OK" "SUCCESS" "HEALTH"
        }
    } catch {
        Write-Log "SharePoint: FAILED" "ERROR" "HEALTH"
    }
    
    # Test Disque
    $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
    $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    if ($diskFreeGB -gt 1) {
        $healthStatus.DiskSpace = $true
        Write-Log "DiskSpace: $diskFreeGB GB" "SUCCESS" "HEALTH"
    } else {
        Write-Log "DiskSpace: CRITICAL $diskFreeGB GB" "ERROR" "HEALTH"
    }
    
    # Test Mémoire
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $memFree = $os.FreePhysicalMemory / 1MB
    if ($memFree -gt 100) {
        $healthStatus.Memory = $true
        Write-Log "Memory: $([math]::Round($memFree))MB free" "SUCCESS" "HEALTH"
    } else {
        Write-Log "Memory: CRITICAL $([math]::Round($memFree))MB" "ERROR" "HEALTH"
    }
    
    # Déterminer statut global
    $healthyCount = ($healthStatus.Values | Where-Object { $_ -eq $true }).Count
    if ($healthyCount -ge 2) {
        Write-Log "Health: $healthyCount/3 checks OK" "SUCCESS" "HEALTH"
        return $true
    } else {
        Write-Log "Health: $healthyCount/3 checks - UNHEALTHY" "CRITICAL" "HEALTH"
        return $false
    }
}

# ════════════════════════════════════════════════════
# v13.0: FONCTION ROLLBACK AUTOMATIQUE
# ════════════════════════════════════════════════════
function Invoke-AutoRollback {
    param($Reason = "Unknown")
    
    Write-Log "ROLLBACK DÉCLENCHÉ: $Reason" "CRITICAL" "ROLLBACK"
    
    try {
        # Sauvegarder état actuel
        $backupPath = "C:\SYAGA-ATLAS\agent_v$($script:Version)_failed.ps1"
        Copy-Item "C:\SYAGA-ATLAS\agent.ps1" $backupPath -Force
        Write-Log "Backup v$($script:Version) sauvegardé" "INFO" "ROLLBACK"
        
        # Créer commande ROLLBACK dans SharePoint
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $token = $tokenResponse.access_token
        
        # Créer commande ROLLBACK
        $rollbackData = @{
            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
            Title = "ROLLBACK_AUTO"
            CommandType = "ROLLBACK"
            Status = "EXECUTED"
            TargetVersion = $script:RollbackConfig.PreviousVersion
            TargetHostname = $hostname
            Parameters = @{
                FromVersion = $script:Version
                ToVersion = $script:RollbackConfig.PreviousVersion
                Reason = $Reason
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ErrorCount = $script:LogCounters.ERROR
            } | ConvertTo-Json
        } | ConvertTo-Json -Depth 10
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
        }
        
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $rollbackData
        
        Write-Log "Commande ROLLBACK créée" "SUCCESS" "ROLLBACK"
        
        # Télécharger version précédente
        $previousUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$($script:RollbackConfig.PreviousVersion).ps1"
        $tempPath = "C:\SYAGA-ATLAS\agent_rollback.ps1"
        
        Invoke-WebRequest -Uri $previousUrl -OutFile $tempPath -UseBasicParsing
        
        if (Test-Path $tempPath) {
            # Arrêter tâche
            Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            
            # Remplacer
            Move-Item $tempPath "C:\SYAGA-ATLAS\agent.ps1" -Force
            
            # Relancer
            Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent"
            
            Write-Log "ROLLBACK RÉUSSI vers v$($script:RollbackConfig.PreviousVersion)" "SUCCESS" "ROLLBACK"
            
            # Terminer ce script
            exit 0
        } else {
            Write-Log "Impossible de télécharger v$($script:RollbackConfig.PreviousVersion)" "ERROR" "ROLLBACK"
        }
        
    } catch {
        Write-Log "ROLLBACK ÉCHOUÉ: $_" "ERROR" "ROLLBACK"
    }
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT (identique v11.1 + health)
# ════════════════════════════════════════════════════
function Send-HeartbeatWithLogs {
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
        
        # CPU
        $cpu = Get-WmiObject -Class Win32_Processor
        $cpuUsage = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average)
        
        # MEMOIRE
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $memTotal = $os.TotalVisibleMemorySize
        $memFree = $os.FreePhysicalMemory
        $memUsage = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)
        
        # DISQUE
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        
        # IP
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        Write-Log "Metriques: CPU=$cpuUsage% MEM=$memUsage% DISK=$diskFreeGB GB" "INFO" "METRICS"
        
        # Métriques détaillées
        $processes = (Get-Process).Count
        $services = (Get-Service | Where-Object { $_.Status -eq "Running" }).Count
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        
        # v13.0: Ajouter statut rollback
        $rollbackStatus = @{
            Enabled = $true
            PreviousVersion = $script:RollbackConfig.PreviousVersion
            ErrorCount = $script:LogCounters.ERROR
            MaxErrors = $script:RollbackConfig.MaxErrorCount
            History = $script:RollbackConfig.RollbackHistory
        } | ConvertTo-Json -Compress
        
        # Pas de filtre (v10.7 fix)
        $existing = @{ d = @{ results = @() } }
        
        # DONNÉES
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
            Logs = ($script:LogsBuffer | Select-Object -Last 100 | ForEach-Object { $_.Text }) -join "`r`n"
            LogsJSON = ($script:LogsBuffer | Select-Object -Last 50 | ForEach-Object { $_.Json } | ConvertTo-Json -Compress)
            LogCounters = $script:LogCounters | ConvertTo-Json -Compress
            ProcessCount = $processes
            ServiceCount = $services
            RollbackStatus = $rollbackStatus  # v13.0: Nouveau champ
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Toujours créer
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        Write-Log "Heartbeat OK (v13.0 + Rollback)" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN - v13.0 AVEC VALIDATION SANTÉ
# ════════════════════════════════════════════════════
Write-Log "Agent v$($script:Version) - ROLLBACK AUTO" "SUCCESS"
Write-Log "v13.0: Rollback automatique < 30 sec" "SUCCESS" "STARTUP"
Write-Log "Config: MaxErrors=$($script:RollbackConfig.MaxErrorCount), Timeout=$($script:RollbackConfig.HealthcheckTimeout)s" "INFO" "CONFIG"

# v13.0: Healthcheck initial
$startTime = Get-Date
Write-Log "Healthcheck initial..." "INFO" "STARTUP"

$isHealthy = Test-AgentHealth

$elapsed = ((Get-Date) - $startTime).TotalSeconds
Write-Log "Healthcheck terminé en $([math]::Round($elapsed, 1))s" "INFO" "STARTUP"

if (!$isHealthy) {
    Write-Log "Agent UNHEALTHY - Rollback dans 10 secondes..." "CRITICAL" "STARTUP"
    Start-Sleep -Seconds 10
    
    # Re-test rapide
    $isHealthy = Test-AgentHealth
    if (!$isHealthy) {
        Invoke-AutoRollback -Reason "HealthcheckFailed"
    } else {
        Write-Log "Agent récupéré après 2ème test" "WARNING" "STARTUP"
    }
}

# Envoi heartbeat
Send-HeartbeatWithLogs

# v13.0: Résumé avec rollback info
Write-Log "Résumé: INFO=$($script:LogCounters.INFO) WARN=$($script:LogCounters.WARNING) ERR=$($script:LogCounters.ERROR)/$($script:RollbackConfig.MaxErrorCount) OK=$($script:LogCounters.SUCCESS)" "INFO" "SUMMARY"
Write-Log "Rollback: v$($script:Version) → v$($script:RollbackConfig.PreviousVersion) si $($script:RollbackConfig.MaxErrorCount) erreurs" "INFO" "SUMMARY"
Write-Log "Fin execution v13.0" "INFO" "SHUTDOWN"
exit 0