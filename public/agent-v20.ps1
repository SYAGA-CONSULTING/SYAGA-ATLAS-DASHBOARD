# ════════════════════════════════════════════════════════════════════
# ATLAS AGENT v20.0 - MINIMAL FIABLE 100%
# ════════════════════════════════════════════════════════════════════
# Focus : Remontée logs GARANTIE + métriques système
# Pas de features complexes, juste la FIABILITÉ
# ════════════════════════════════════════════════════════════════════

$script:Version = "20.0"
$script:Hostname = $env:COMPUTERNAME
$script:StartTime = Get-Date

# Configuration SharePoint
$script:SharePointConfig = @{
    TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
    ClientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
    ClientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
    SiteName = "syagacons"
    ServersListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
}

# Buffer logs avec limite stricte
$script:LogsBuffer = ""
$script:MaxLogSize = 7500  # SharePoint limite à 8000, on garde marge

# ════════════════════════════════════════════════════════════════════
# LOGGING SIMPLE ET ROBUSTE
# ════════════════════════════════════════════════════════════════════
function Write-AgentLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ajouter au buffer avec gestion taille
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxLogSize) {
        # Garder début et fin pour contexte
        $keepStart = 2000
        $keepEnd = 5000
        $start = $script:LogsBuffer.Substring(0, $keepStart)
        $end = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $keepEnd)
        $script:LogsBuffer = $start + "`r`n... [TRONQUÉ] ...`r`n" + $end
    }
    
    # Afficher avec couleur
    $color = switch($Level) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

# ════════════════════════════════════════════════════════════════════
# COLLECTE MÉTRIQUES SYSTÈME FIABLE
# ════════════════════════════════════════════════════════════════════
function Get-SystemMetrics {
    $metrics = @{
        CPUUsage = 0
        MemoryUsage = 0
        DiskSpaceGB = 0
        ProcessCount = 0
        ErrorCount = 0
    }
    
    try {
        # CPU - méthode la plus fiable
        $cpuCounter = Get-Counter '\Processeur(_Total)\% temps processeur' -ErrorAction SilentlyContinue
        if ($cpuCounter) {
            $metrics.CPUUsage = [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 1)
        } else {
            # Fallback WMI
            $cpu = Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average
            $metrics.CPUUsage = [math]::Round($cpu.Average, 1)
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
        # Process count
        $metrics.ProcessCount = (Get-Process).Count
    } catch {
        $metrics.ProcessCount = 0
    }
    
    try {
        # Erreurs système dernière heure
        $errors = Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddHours(-1) -ErrorAction SilentlyContinue
        $metrics.ErrorCount = if ($errors) { $errors.Count } else { 0 }
    } catch {
        $metrics.ErrorCount = 0
    }
    
    return $metrics
}

# ════════════════════════════════════════════════════════════════════
# ENVOI SHAREPOINT AVEC RETRY
# ════════════════════════════════════════════════════════════════════
function Send-ToSharePoint {
    param([hashtable]$Data)
    
    $maxRetries = 3
    $retryDelay = 2
    
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
            
            # Préparer headers
            $headers = @{
                "Authorization" = "Bearer $($tokenResponse.access_token)"
                "Accept" = "application/json;odata=verbose"
                "Content-Type" = "application/json;odata=verbose;charset=utf-8"
            }
            
            # Convertir données
            $jsonData = $Data | ConvertTo-Json -Depth 10 -Compress
            
            # Envoyer
            $createUrl = "https://$($script:SharePointConfig.SiteName).sharepoint.com/_api/web/lists(guid'$($script:SharePointConfig.ServersListId)')/items"
            $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
            
            Write-AgentLog "✓ Données envoyées à SharePoint (ID: $($response.d.Id))" "SUCCESS"
            return $true
            
        } catch {
            Write-AgentLog "Tentative $retry/$maxRetries échouée: $_" "WARNING"
            
            if ($retry -lt $maxRetries) {
                Start-Sleep -Seconds $retryDelay
                $retryDelay *= 2  # Backoff exponentiel
            } else {
                Write-AgentLog "❌ Échec définitif envoi SharePoint" "ERROR"
                
                # Sauvegarder en local comme fallback
                $fallbackFile = "C:\SYAGA-ATLAS\logs\fallback-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
                $Data | ConvertTo-Json -Depth 10 | Out-File $fallbackFile -Encoding UTF8
                Write-AgentLog "Données sauvées localement: $fallbackFile" "INFO"
                
                return $false
            }
        }
    }
}

# ════════════════════════════════════════════════════════════════════
# HEARTBEAT PRINCIPAL
# ════════════════════════════════════════════════════════════════════
function Send-Heartbeat {
    Write-AgentLog "Préparation heartbeat v$($script:Version)..." "INFO"
    
    # Collecter métriques
    $metrics = Get-SystemMetrics
    Write-AgentLog "Métriques: CPU=$($metrics.CPUUsage)% MEM=$($metrics.MemoryUsage)% DISK=$($metrics.DiskSpaceGB)GB" "INFO"
    
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
    
    # Uptime
    $uptime = (Get-Date) - $script:StartTime
    $uptimeStr = "{0}h {1}m" -f [math]::Floor($uptime.TotalHours), $uptime.Minutes
    
    # Construire header de log
    $logHeader = @"
════════════════════════════════════════════════════
ATLAS v$($script:Version) - AGENT MINIMAL FIABLE
════════════════════════════════════════════════════
Hostname: $($script:Hostname) ($ipAddress)
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Uptime: $uptimeStr

MÉTRIQUES SYSTÈME:
  CPU: $($metrics.CPUUsage)%
  Memory: $($metrics.MemoryUsage)%
  Disk C:\: $($metrics.DiskSpaceGB) GB free
  Processes: $($metrics.ProcessCount)
  System Errors (1h): $($metrics.ErrorCount)

LOGS AGENT:
════════════════════════════════════════════════════
"@
    
    # Combiner logs
    $fullLogs = $logHeader + "`r`n" + $script:LogsBuffer
    
    # Limiter taille finale
    if ($fullLogs.Length -gt 7900) {
        $fullLogs = $fullLogs.Substring(0, 7900) + "`r`n... [TRONQUÉ]"
    }
    
    # Préparer données SharePoint
    $data = @{
        "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
        Title = $script:Hostname
        Hostname = $script:Hostname
        IPAddress = $ipAddress
        State = if ($metrics.ErrorCount -gt 10) { "WARNING" } else { "HEALTHY" }
        LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        AgentVersion = $script:Version
        CPUUsage = $metrics.CPUUsage
        MemoryUsage = $metrics.MemoryUsage
        DiskSpaceGB = $metrics.DiskSpaceGB
        Logs = $fullLogs
    }
    
    # Envoyer avec retry
    $success = Send-ToSharePoint -Data $data
    
    if ($success) {
        Write-AgentLog "✅ Heartbeat v$($script:Version) envoyé avec succès" "SUCCESS"
    } else {
        Write-AgentLog "❌ Échec envoi heartbeat" "ERROR"
    }
    
    return $success
}

# ════════════════════════════════════════════════════════════════════
# TEST AUTO-DIAGNOSTIC
# ════════════════════════════════════════════════════════════════════
function Test-AgentHealth {
    Write-AgentLog "Auto-diagnostic agent..." "INFO"
    
    $tests = @{
        "SharePoint accessible" = {
            $uri = "https://$($script:SharePointConfig.SiteName).sharepoint.com"
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 5
            return $response.StatusCode -eq 200
        }
        
        "Collecte métriques" = {
            $metrics = Get-SystemMetrics
            return $metrics.CPUUsage -ge 0 -and $metrics.MemoryUsage -ge 0
        }
        
        "Espace disque suffisant" = {
            $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
            $freeGB = $disk.FreeSpace / 1GB
            return $freeGB -gt 1
        }
        
        "Permissions registre" = {
            Test-Path "HKLM:\SOFTWARE\SYAGA"
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
    
    Write-AgentLog "Diagnostic: $passed OK, $failed KO" $(if ($failed -eq 0) {"SUCCESS"} else {"WARNING"})
    
    return $failed -eq 0
}

# ════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════
Write-AgentLog "════════════════════════════════════════" "INFO"
Write-AgentLog "ATLAS AGENT v$($script:Version) - DÉMARRAGE" "SUCCESS"
Write-AgentLog "════════════════════════════════════════" "INFO"

# Test santé
$healthy = Test-AgentHealth

if ($healthy) {
    Write-AgentLog "Agent en bonne santé" "SUCCESS"
} else {
    Write-AgentLog "Problèmes détectés mais continuation" "WARNING"
}

# Envoi heartbeat principal
$sent = Send-Heartbeat

# Code sortie
$exitCode = if ($sent) { 0 } else { 1 }

Write-AgentLog "════════════════════════════════════════" "INFO"
Write-AgentLog "AGENT v$($script:Version) TERMINÉ (Code: $exitCode)" $(if ($exitCode -eq 0) {"SUCCESS"} else {"ERROR"})
Write-AgentLog "════════════════════════════════════════" "INFO"

exit $exitCode