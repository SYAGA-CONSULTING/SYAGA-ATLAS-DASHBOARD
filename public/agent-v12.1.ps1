# ATLAS Agent v12.1 - FIX ERREUR 400 + LOGS ENRICHIS
$script:Version = "12.1"
$hostname = $env:COMPUTERNAME
$logFile = "C:\SYAGA-ATLAS\atlas_log.txt"
$jsonLogFile = "C:\SYAGA-ATLAS\atlas_log.json"

# ════════════════════════════════════════════════════
# SHAREPOINT CONFIG
# ════════════════════════════════════════════════════
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

# ════════════════════════════════════════════════════
# v12.0 : SYSTÈME DE LOGS AVANCÉ
# ════════════════════════════════════════════════════
# Buffer circulaire de 1000 lignes
$script:LogsBuffer = @()
$script:MaxBufferSize = 1000

# Compteurs pour analyse
$script:LogCounters = @{
    INFO = 0
    WARNING = 0
    ERROR = 0
    SUCCESS = 0
    DEBUG = 0
}

# ════════════════════════════════════════════════════
# FONCTION LOG v12.0 - ENRICHIE
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
    
    # Afficher
    switch($Level) {
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
# FONCTION HEARTBEAT (MÉTHODE v9.1 QUI MARCHE)
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
        
        # v12.0 : Métriques détaillées supplémentaires
        $processes = (Get-Process).Count
        $services = (Get-Service | Where-Object { $_.Status -eq "Running" }).Count
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        
        Write-Log "Details: Processes=$processes Services=$services Uptime=$($uptime.TotalHours.ToString('F1'))h" "DEBUG" "METRICS"
        
        # v10.7 : Toujours créer une nouvelle entrée (pas de recherche)
        # Cela évite l'erreur 500 sur le filtre
        $existing = @{ d = @{ results = @() } }  # Simule aucune entrée trouvée
        
        # DONNÉES - v12.1: Sans champs problématiques
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
        }
        
        # v12.1: Ajouter LogsJSON et LogCounters seulement si petits
        $logsJson = ($script:LogsBuffer | Select-Object -Last 20 | ForEach-Object { $_.Json } | ConvertTo-Json -Compress)
        if ($logsJson.Length -lt 5000) {
            $data.LogsJSON = $logsJson
        }
        
        $countersJson = $script:LogCounters | ConvertTo-Json -Compress
        if ($countersJson.Length -lt 1000) {
            $data.LogCounters = $countersJson
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        if ($existing.d.results.Count -gt 0) {
            # Update
            $itemId = $existing.d.results[0].Id
            $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items($itemId)"
            
            $updateHeaders = $headers + @{
                "X-HTTP-Method" = "MERGE"
                "IF-MATCH" = "*"
            }
            
            Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $jsonData
            Write-Log "Heartbeat OK" "SUCCESS"
        } else {
            # Create
            $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
            Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
            Write-Log "Heartbeat cree" "SUCCESS"
        }
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN - SIMPLE ET COURT
# ════════════════════════════════════════════════════
Write-Log "Agent v$($script:Version) - FIX 400" "SUCCESS"
Write-Log "Pas d'auto-update (gere par updater.ps1)"
Write-Log "v12.1: Fix erreur 400 + Logs optimisés" "SUCCESS" "STARTUP"
Write-Log "Buffer: $($script:MaxBufferSize) lignes, JSON léger" "INFO" "CONFIG"

Send-HeartbeatWithLogs

# v12.0 : Résumé des logs
Write-Log "Résumé: INFO=$($script:LogCounters.INFO) WARN=$($script:LogCounters.WARNING) ERR=$($script:LogCounters.ERROR) OK=$($script:LogCounters.SUCCESS)" "INFO" "SUMMARY"
Write-Log "Fin execution v12.1" "INFO" "SHUTDOWN"
exit 0