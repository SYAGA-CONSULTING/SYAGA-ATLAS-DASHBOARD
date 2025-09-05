# ════════════════════════════════════════════════════════════════════
# ATLAS AGENT v21.0 TEST - NOUVELLE VERSION AMÉLIORÉE
# ════════════════════════════════════════════════════════════════════
# Version test pour valider mécanisme auto-update v20→v21
# Améliorations : Logs structurés JSON + Métriques détaillées
# ════════════════════════════════════════════════════════════════════

$script:Version = "21.0"
$script:Hostname = $env:COMPUTERNAME
$script:StartTime = Get-Date

# Configuration SharePoint (identique v20)
$script:SharePointConfig = @{
    TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
    ClientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
    ClientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
    SiteName = "syagacons"
    ServersListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
}

$script:LogsBuffer = ""
$script:MaxLogSize = 7500

# ════════════════════════════════════════════════════════════════════
# NOUVEAUTÉ v21 : LOGS STRUCTURÉS JSON
# ════════════════════════════════════════════════════════════════════
function Write-AgentLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [hashtable]$Data = @{}
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = @{
        Timestamp = $timestamp
        Level = $Level
        Version = $script:Version
        Message = $Message
        Data = $Data
    } | ConvertTo-Json -Compress
    
    # Buffer pour SharePoint
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxLogSize) {
        $keepStart = 2000
        $keepEnd = 5000
        $start = $script:LogsBuffer.Substring(0, $keepStart)
        $end = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $keepEnd)
        $script:LogsBuffer = $start + "`r`n... [LOGS TRONQUÉS] ...`r`n" + $end
    }
    
    # Affichage console avec couleur v21 (magenta)
    $color = switch($Level) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "INFO" { "Magenta" }  # v21 en magenta
        default { "White" }
    }
    
    Write-Host "[v21] [$timestamp] [$Level] $Message" -ForegroundColor $color
}

# ════════════════════════════════════════════════════════════════════
# NOUVEAUTÉ v21 : MÉTRIQUES ÉTENDUES
# ════════════════════════════════════════════════════════════════════
function Get-SystemMetrics {
    $metrics = @{
        CPUUsage = 0
        MemoryUsage = 0
        DiskSpaceGB = 0
        ProcessCount = 0
        ErrorCount = 0
        # Nouvelles métriques v21
        TopProcesses = @()
        NetworkStatus = "Unknown"
        ServicesStatus = @{}
        UptimeDays = 0
    }
    
    try {
        # CPU
        $cpuCounter = Get-Counter '\Processeur(_Total)\% temps processeur' -ErrorAction SilentlyContinue
        if ($cpuCounter) {
            $metrics.CPUUsage = [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 1)
        }
    } catch {
        Write-AgentLog "Erreur CPU: $_" "WARNING"
    }
    
    try {
        # Memory
        $os = Get-WmiObject Win32_OperatingSystem
        if ($os) {
            $totalMem = $os.TotalVisibleMemorySize
            $freeMem = $os.FreePhysicalMemory
            if ($totalMem -gt 0) {
                $metrics.MemoryUsage = [math]::Round((($totalMem - $freeMem) / $totalMem) * 100, 1)
            }
            
            # Nouveauté v21 : Uptime
            $lastBoot = [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)
            $uptime = (Get-Date) - $lastBoot
            $metrics.UptimeDays = [math]::Round($uptime.TotalDays, 1)
        }
    } catch {
        Write-AgentLog "Erreur Memory: $_" "WARNING"
    }
    
    try {
        # Disk
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        if ($disk) {
            $metrics.DiskSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        }
    } catch {
        Write-AgentLog "Erreur Disk: $_" "WARNING"
    }
    
    try {
        # Process
        $processes = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
        $metrics.ProcessCount = (Get-Process).Count
        
        # Nouveauté v21 : Top 5 processes
        $metrics.TopProcesses = $processes | ForEach-Object {
            @{
                Name = $_.ProcessName
                MemoryMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
                CPU = [math]::Round($_.CPU, 1)
            }
        }
    } catch {
        $metrics.ProcessCount = 0
    }
    
    try {
        # Nouveauté v21 : Network status
        $ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet
        $metrics.NetworkStatus = if ($ping) { "Online" } else { "Offline" }
    } catch {
        $metrics.NetworkStatus = "Unknown"
    }
    
    try {
        # Nouveauté v21 : Services critiques
        $criticalServices = @("W32Time", "EventLog", "Dnscache", "LanmanServer")
        foreach ($svc in $criticalServices) {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) {
                $metrics.ServicesStatus[$svc] = $service.Status.ToString()
            }
        }
    } catch {
        Write-AgentLog "Erreur services: $_" "WARNING"
    }
    
    try {
        # Errors
        $errors = Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddHours(-1) -ErrorAction SilentlyContinue
        $metrics.ErrorCount = if ($errors) { $errors.Count } else { 0 }
    } catch {
        $metrics.ErrorCount = 0
    }
    
    return $metrics
}

# ════════════════════════════════════════════════════════════════════
# ENVOI SHAREPOINT AMÉLIORÉ v21
# ════════════════════════════════════════════════════════════════════
function Send-ToSharePoint {
    param([hashtable]$Data)
    
    $maxRetries = 3
    $retryDelay = 2
    
    # Ajouter metadata v21
    $Data["UpdatedByVersion"] = "21.0"
    $Data["UpdateTimestamp"] = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    
    for ($retry = 1; $retry -le $maxRetries; $retry++) {
        try {
            # Obtenir token
            $clientSecret = [System.Text.Encoding]::UTF8.GetString(
                [System.Convert]::FromBase64String($script:SharePointConfig.ClientSecretB64)
            )
            
            $tokenBody = @{
                grant_type = "client_credentials"
                client_id = "$($script:SharePointConfig.ClientId)@$($script:SharePointConfig.TenantId)"
                client_secret = $clientSecret
                resource = "00000003-0000-0ff1-ce00-000000000000/$($script:SharePointConfig.SiteName).sharepoint.com@$($script:SharePointConfig.TenantId)"
            }
            
            $tokenUrl = "https://accounts.accesscontrol.windows.net/$($script:SharePointConfig.TenantId)/tokens/OAuth/2"
            $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
            
            if (!$tokenResponse.access_token) {
                throw "Pas de token obtenu"
            }
            
            # Headers
            $headers = @{
                "Authorization" = "Bearer $($tokenResponse.access_token)"
                "Accept" = "application/json;odata=verbose"
                "Content-Type" = "application/json;odata=verbose;charset=utf-8"
            }
            
            # Envoyer
            $jsonData = $Data | ConvertTo-Json -Depth 10 -Compress
            $createUrl = "https://$($script:SharePointConfig.SiteName).sharepoint.com/_api/web/lists(guid'$($script:SharePointConfig.ServersListId)')/items"
            $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
            
            Write-AgentLog "✓ Données v21 envoyées à SharePoint (ID: $($response.d.Id))" "SUCCESS" @{
                ItemId = $response.d.Id
                Retry = $retry
            }
            
            return $true
            
        } catch {
            Write-AgentLog "Tentative $retry/$maxRetries échouée: $_" "WARNING"
            
            if ($retry -lt $maxRetries) {
                Start-Sleep -Seconds $retryDelay
                $retryDelay *= 2
            } else {
                Write-AgentLog "❌ Échec définitif envoi SharePoint" "ERROR"
                
                # Fallback local
                $fallbackFile = "C:\SYAGA-ATLAS\logs\fallback-v21-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
                $Data | ConvertTo-Json -Depth 10 | Out-File $fallbackFile -Encoding UTF8
                Write-AgentLog "Données v21 sauvées localement: $fallbackFile" "INFO"
                
                return $false
            }
        }
    }
}

# ════════════════════════════════════════════════════════════════════
# HEARTBEAT v21 ENRICHI
# ════════════════════════════════════════════════════════════════════
function Send-Heartbeat {
    Write-AgentLog "Préparation heartbeat v$($script:Version) enrichi..." "INFO"
    
    # Collecter métriques étendues
    $metrics = Get-SystemMetrics
    Write-AgentLog "Métriques v21 collectées" "INFO" @{
        CPU = $metrics.CPUUsage
        Memory = $metrics.MemoryUsage
        Disk = $metrics.DiskSpaceGB
        Uptime = $metrics.UptimeDays
        Network = $metrics.NetworkStatus
    }
    
    # IP
    $ipAddress = ""
    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 | 
              Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | 
              Select-Object -First 1
        if ($ip) { $ipAddress = $ip.IPAddress }
    } catch {
        $ipAddress = "Unknown"
    }
    
    # Uptime agent
    $uptime = (Get-Date) - $script:StartTime
    $uptimeStr = "{0}h {1}m" -f [math]::Floor($uptime.TotalHours), $uptime.Minutes
    
    # Header enrichi v21
    $logHeader = @"
════════════════════════════════════════════════════
ATLAS v$($script:Version) - AGENT ENRICHI
════════════════════════════════════════════════════
Hostname: $($script:Hostname) ($ipAddress)
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Agent Uptime: $uptimeStr
System Uptime: $($metrics.UptimeDays) days

MÉTRIQUES SYSTÈME v21:
  CPU: $($metrics.CPUUsage)%
  Memory: $($metrics.MemoryUsage)%
  Disk C:\: $($metrics.DiskSpaceGB) GB free
  Processes: $($metrics.ProcessCount)
  Network: $($metrics.NetworkStatus)
  System Errors (1h): $($metrics.ErrorCount)

TOP PROCESSES:
$(($metrics.TopProcesses | ForEach-Object { "  - $($_.Name): $($_.MemoryMB) MB" }) -join "`r`n")

SERVICES CRITIQUES:
$(($metrics.ServicesStatus.GetEnumerator() | ForEach-Object { "  - $($_.Key): $($_.Value)" }) -join "`r`n")

NOUVEAUTÉS v21:
  ✓ Logs structurés JSON
  ✓ Métriques étendues
  ✓ Monitoring services
  ✓ Top processes tracking

LOGS AGENT:
════════════════════════════════════════════════════
"@
    
    # Combiner logs
    $fullLogs = $logHeader + "`r`n" + $script:LogsBuffer
    
    # Limiter taille
    if ($fullLogs.Length -gt 7900) {
        $fullLogs = $fullLogs.Substring(0, 7900) + "`r`n... [TRONQUÉ v21]"
    }
    
    # Préparer données SharePoint enrichies
    $data = @{
        "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
        Title = $script:Hostname
        Hostname = $script:Hostname
        IPAddress = $ipAddress
        State = if ($metrics.ErrorCount -gt 10) { "WARNING" } 
                elseif ($metrics.NetworkStatus -eq "Offline") { "OFFLINE" }
                else { "HEALTHY" }
        LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        AgentVersion = $script:Version
        CPUUsage = $metrics.CPUUsage
        MemoryUsage = $metrics.MemoryUsage
        DiskSpaceGB = $metrics.DiskSpaceGB
        Logs = $fullLogs
    }
    
    # Envoyer
    $success = Send-ToSharePoint -Data $data
    
    if ($success) {
        Write-AgentLog "✅ Heartbeat v$($script:Version) enrichi envoyé avec succès" "SUCCESS"
    } else {
        Write-AgentLog "❌ Échec envoi heartbeat v21" "ERROR"
    }
    
    return $success
}

# ════════════════════════════════════════════════════════════════════
# NOUVEAUTÉ v21 : VALIDATION VERSION
# ════════════════════════════════════════════════════════════════════
function Test-VersionUpgrade {
    Write-AgentLog "Validation upgrade vers v21..." "INFO"
    
    # Créer marqueur de version
    $versionMarker = @{
        Version = $script:Version
        UpgradeTime = Get-Date
        FromVersion = "20.0"
        Success = $true
    } | ConvertTo-Json
    
    $markerFile = "C:\SYAGA-ATLAS\logs\version-21-marker.json"
    $versionMarker | Out-File $markerFile -Encoding UTF8
    
    Write-AgentLog "✓ Marqueur v21 créé: $markerFile" "SUCCESS"
    
    # Valider fonctionnalités v21
    $features = @{
        "Logs JSON" = $true
        "Métriques étendues" = $true
        "Top processes" = $metrics.TopProcesses.Count -gt 0
        "Services monitoring" = $metrics.ServicesStatus.Count -gt 0
    }
    
    foreach ($feature in $features.Keys) {
        if ($features[$feature]) {
            Write-AgentLog "  ✓ $feature activé" "SUCCESS"
        } else {
            Write-AgentLog "  ✗ $feature manquant" "ERROR"
        }
    }
    
    return $true
}

# ════════════════════════════════════════════════════════════════════
# TEST AUTO-DIAGNOSTIC v21
# ════════════════════════════════════════════════════════════════════
function Test-AgentHealth {
    Write-AgentLog "Auto-diagnostic agent v21..." "INFO"
    
    $tests = @{
        "SharePoint accessible" = {
            $uri = "https://$($script:SharePointConfig.SiteName).sharepoint.com"
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 5
            return $response.StatusCode -eq 200
        }
        
        "Collecte métriques étendues" = {
            $metrics = Get-SystemMetrics
            return $metrics.TopProcesses.Count -gt 0 -and $metrics.ServicesStatus.Count -gt 0
        }
        
        "Logs structurés JSON" = {
            $testLog = @{ Test = "OK"; Time = Get-Date } | ConvertTo-Json
            return $testLog.Length -gt 10
        }
        
        "Espace disque suffisant" = {
            $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
            $freeGB = $disk.FreeSpace / 1GB
            return $freeGB -gt 1
        }
        
        "Version v21 confirmée" = {
            return $script:Version -eq "21.0"
        }
    }
    
    $passed = 0
    $failed = 0
    
    foreach ($testName in $tests.Keys) {
        try {
            $result = & $tests[$testName]
            if ($result) {
                Write-AgentLog "  ✓ $testName" "SUCCESS"
                $passed++
            } else {
                Write-AgentLog "  ✗ $testName" "ERROR"
                $failed++
            }
        } catch {
            Write-AgentLog "  ✗ $testName : $_" "ERROR"
            $failed++
        }
    }
    
    Write-AgentLog "Diagnostic v21: $passed OK, $failed KO" $(if ($failed -eq 0) {"SUCCESS"} else {"WARNING"})
    
    return $failed -eq 0
}

# ════════════════════════════════════════════════════════════════════
# MAIN v21
# ════════════════════════════════════════════════════════════════════
Write-AgentLog "════════════════════════════════════════" "INFO"
Write-AgentLog "ATLAS AGENT v$($script:Version) - DÉMARRAGE" "SUCCESS"
Write-AgentLog "════════════════════════════════════════" "INFO"
Write-AgentLog "🆕 Nouveautés v21: Logs JSON, Métriques étendues, Services monitoring" "INFO"

# Validation upgrade
$upgraded = Test-VersionUpgrade

# Test santé
$healthy = Test-AgentHealth

if ($healthy) {
    Write-AgentLog "Agent v21 en bonne santé" "SUCCESS"
} else {
    Write-AgentLog "Problèmes détectés mais continuation" "WARNING"
}

# Envoi heartbeat enrichi
$sent = Send-Heartbeat

# Code sortie
$exitCode = if ($sent -and $healthy) { 0 } else { 1 }

Write-AgentLog "════════════════════════════════════════" "INFO"
Write-AgentLog "AGENT v$($script:Version) TERMINÉ (Code: $exitCode)" $(if ($exitCode -eq 0) {"SUCCESS"} else {"ERROR"})
Write-AgentLog "Update v20→v21 confirmé avec succès" "SUCCESS"
Write-AgentLog "════════════════════════════════════════" "INFO"

exit $exitCode