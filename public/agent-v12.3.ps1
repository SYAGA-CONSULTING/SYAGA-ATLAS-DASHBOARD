# ATLAS Agent v12.3 - LOGS ENRICHIS SANS ERREUR 400
$script:Version = "12.3"
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

# ════════════════════════════════════════════════════
# v12.3 : LOGS ENRICHIS STRUCTURÉS
# ════════════════════════════════════════════════════
$script:LogsBuffer = ""
$script:MaxBufferSize = 10000  # 10KB max

# Compteurs de logs
$script:LogStats = @{
    INFO = 0
    WARNING = 0
    ERROR = 0
    SUCCESS = 0
    DEBUG = 0
    TotalLines = 0
}

# Métriques détaillées
$script:Metrics = @{
    Processes = 0
    Services = 0
    UptimeHours = 0
    EventErrors = 0
    DiskIOps = 0
}

# ════════════════════════════════════════════════════
# FONCTION LOG ENRICHIE
# ════════════════════════════════════════════════════
function Write-Log {
    param(
        $Message, 
        $Level = "INFO",
        $Component = "MAIN"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [$Component] $Message"
    
    # Ajouter au buffer avec gestion taille
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxBufferSize) {
        # Garder seulement la fin
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $script:MaxBufferSize)
    }
    
    # Stats
    $script:LogStats[$Level]++
    $script:LogStats.TotalLines++
    
    # Afficher avec couleurs
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Gray }
        default { Write-Host $logEntry }
    }
    
    # Fichier log
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# COLLECTE MÉTRIQUES AVANCÉES
# ════════════════════════════════════════════════════
function Get-AdvancedMetrics {
    try {
        # Processes et Services
        $script:Metrics.Processes = (Get-Process).Count
        $script:Metrics.Services = (Get-Service | Where-Object { $_.Status -eq "Running" }).Count
        
        # Uptime
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $script:Metrics.UptimeHours = [math]::Round($uptime.TotalHours, 1)
        
        # Event Log Errors (dernières 24h)
        try {
            $yesterday = (Get-Date).AddDays(-1)
            $script:Metrics.EventErrors = (Get-WinEvent -FilterHashtable @{LogName='System'; Level=2; StartTime=$yesterday} -ErrorAction SilentlyContinue).Count
        } catch {
            $script:Metrics.EventErrors = 0
        }
        
        # Disk I/O
        try {
            $diskPerf = Get-Counter "\PhysicalDisk(_Total)\Disk Transfers/sec" -ErrorAction SilentlyContinue
            $script:Metrics.DiskIOps = [math]::Round($diskPerf.CounterSamples[0].CookedValue, 0)
        } catch {
            $script:Metrics.DiskIOps = 0
        }
        
        Write-Log "Métriques: Proc=$($script:Metrics.Processes) Svc=$($script:Metrics.Services) Up=$($script:Metrics.UptimeHours)h Err=$($script:Metrics.EventErrors)" "DEBUG" "METRICS"
        
    } catch {
        Write-Log "Erreur collecte métriques: $_" "WARNING" "METRICS"
    }
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT AVEC LOGS ENRICHIS
# ════════════════════════════════════════════════════
function Send-HeartbeatEnriched {
    try {
        Write-Log "Début heartbeat" "DEBUG" "HEARTBEAT"
        
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
        Write-Log "Token obtenu" "SUCCESS" "AUTH"
        
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
        
        Write-Log "CPU=$cpuUsage% MEM=$memUsage% DISK=$diskFreeGB GB" "INFO" "SYSTEM"
        
        # Collecter métriques avancées
        Get-AdvancedMetrics
        
        # Créer résumé logs enrichi
        $logSummary = @"
=== ATLAS v$($script:Version) ===
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Stats: INFO=$($script:LogStats.INFO) WARN=$($script:LogStats.WARNING) ERR=$($script:LogStats.ERROR) OK=$($script:LogStats.SUCCESS)
Metrics: Proc=$($script:Metrics.Processes) Svc=$($script:Metrics.Services) Up=$($script:Metrics.UptimeHours)h
System: CPU=$cpuUsage% MEM=$memUsage% DISK=$diskFreeGB GB
Events: $($script:Metrics.EventErrors) errors/24h
===
"@
        
        # Ajouter le résumé au début du buffer
        $enrichedLogs = $logSummary + "`r`n" + $script:LogsBuffer
        
        # DONNÉES - Champs de base + logs enrichis
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
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Créer nouvelle entrée
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Heartbeat envoyé avec logs enrichis" "SUCCESS" "HEARTBEAT"
        Write-Log "ID SharePoint: $($response.d.Id)" "DEBUG" "HEARTBEAT"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR" "HEARTBEAT"
    }
}

# ════════════════════════════════════════════════════
# TESTS AU DÉMARRAGE
# ════════════════════════════════════════════════════
function Test-SystemHealth {
    Write-Log "Tests système..." "INFO" "HEALTH"
    
    # Test réseau
    try {
        $ping = Test-Connection "8.8.8.8" -Count 1 -Quiet
        if ($ping) {
            Write-Log "Connectivité Internet OK" "SUCCESS" "HEALTH"
        } else {
            Write-Log "Pas de connectivité Internet" "WARNING" "HEALTH"
        }
    } catch {
        Write-Log "Test réseau échoué" "WARNING" "HEALTH"
    }
    
    # Test services critiques
    $criticalServices = @("Winmgmt", "RpcSs", "LanmanServer")
    foreach ($svc in $criticalServices) {
        $service = Get-Service $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Write-Log "Service $svc OK" "SUCCESS" "HEALTH"
        } else {
            Write-Log "Service $svc KO" "ERROR" "HEALTH"
        }
    }
}

# ════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════
Write-Log "════════════════════════════════" "INFO" "STARTUP"
Write-Log "ATLAS Agent v$($script:Version)" "SUCCESS" "STARTUP"
Write-Log "Logs enrichis activés" "INFO" "STARTUP"
Write-Log "════════════════════════════════" "INFO" "STARTUP"

# Tests système
Test-SystemHealth

# Envoi heartbeat avec logs enrichis
Send-HeartbeatEnriched

# Résumé final
Write-Log "════════════════════════════════" "INFO" "SUMMARY"
Write-Log "Session terminée" "INFO" "SUMMARY"
Write-Log "Total logs: $($script:LogStats.TotalLines) lignes" "INFO" "SUMMARY"
Write-Log "Erreurs: $($script:LogStats.ERROR)" "INFO" "SUMMARY"
Write-Log "════════════════════════════════" "INFO" "SUMMARY"

exit 0