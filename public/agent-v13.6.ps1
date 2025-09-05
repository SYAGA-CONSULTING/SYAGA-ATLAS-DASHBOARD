# ════════════════════════════════════════════════════════════════════
# ATLAS Agent v13.6 - AVEC MÉTRIQUES SYSTÈME COMPLÈTES
# ════════════════════════════════════════════════════════════════════
# - Collecte CPU, Memory, Disk
# - Remontée métriques dans SharePoint
# - Monitoring complet
# ════════════════════════════════════════════════════════════════════

$script:Version = "13.6"
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
$script:MaxBufferSize = 5000

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
}

# ════════════════════════════════════════════════════════════════════
# FONCTION COLLECTE MÉTRIQUES SYSTÈME
# ════════════════════════════════════════════════════════════════════
function Get-SystemMetrics {
    Write-Log "Collecte métriques système..." "DEBUG"
    
    $metrics = @{
        CPUUsage = 0
        MemoryUsage = 0
        MemoryUsedMB = 0
        MemoryTotalMB = 0
        DiskSpaceGB = 0
        DiskTotalGB = 0
        DiskUsedPercent = 0
        IPAddress = ""
    }
    
    try {
        # CPU Usage
        $cpu = Get-WmiObject -Class Win32_Processor
        if ($cpu) {
            $cpuLoad = $cpu | Measure-Object -Property LoadPercentage -Average
            $metrics.CPUUsage = [math]::Round($cpuLoad.Average)
            if ($metrics.CPUUsage -eq 0) {
                # Méthode alternative si LoadPercentage est 0
                $cpuCounter = Get-Counter '\Processeur(_Total)\% temps processeur' -ErrorAction SilentlyContinue
                if ($cpuCounter) {
                    $metrics.CPUUsage = [math]::Round($cpuCounter.CounterSamples[0].CookedValue)
                }
            }
        }
        
        # Memory
        $os = Get-WmiObject -Class Win32_OperatingSystem
        if ($os) {
            $memTotal = $os.TotalVisibleMemorySize
            $memFree = $os.FreePhysicalMemory
            $memUsed = $memTotal - $memFree
            
            $metrics.MemoryTotalMB = [math]::Round($memTotal / 1024, 1)
            $metrics.MemoryUsedMB = [math]::Round($memUsed / 1024, 1)
            $metrics.MemoryUsage = [math]::Round(($memUsed / $memTotal) * 100, 1)
        }
        
        # Disk
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        if ($disk) {
            $diskFree = $disk.FreeSpace
            $diskTotal = $disk.Size
            $diskUsed = $diskTotal - $diskFree
            
            $metrics.DiskSpaceGB = [math]::Round($diskFree / 1GB, 1)
            $metrics.DiskTotalGB = [math]::Round($diskTotal / 1GB, 1)
            $metrics.DiskUsedPercent = [math]::Round(($diskUsed / $diskTotal) * 100, 1)
        }
        
        # IP Address
        $ip = Get-NetIPAddress -AddressFamily IPv4 | 
            Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | 
            Select-Object -First 1
        if ($ip) {
            $metrics.IPAddress = $ip.IPAddress
        }
        
        Write-Log "Métriques: CPU=$($metrics.CPUUsage)% MEM=$($metrics.MemoryUsage)% ($($metrics.MemoryUsedMB)/$($metrics.MemoryTotalMB) MB) DISK=$($metrics.DiskSpaceGB)/$($metrics.DiskTotalGB) GB ($($metrics.DiskUsedPercent)% used)" "INFO"
        
    } catch {
        Write-Log "Erreur collecte métriques: $_" "ERROR"
    }
    
    return $metrics
}

# ════════════════════════════════════════════════════════════════════
# FONCTION HEARTBEAT AVEC MÉTRIQUES
# ════════════════════════════════════════════════════════════════════
function Send-Heartbeat {
    try {
        Write-Log "Préparation heartbeat v$($script:Version)..." "DEBUG"
        
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
        $metrics = Get-SystemMetrics
        
        # Créer header enrichi pour logs
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logHeader = @"
════════════════════════════════════════════════════
ATLAS v$($script:Version) - MONITORING REPORT
════════════════════════════════════════════════════
Hostname: $hostname ($($metrics.IPAddress))
Time: $currentTime

SYSTEM METRICS:
  CPU Usage: $($metrics.CPUUsage)%
  Memory: $($metrics.MemoryUsage)% ($($metrics.MemoryUsedMB) MB / $($metrics.MemoryTotalMB) MB)
  Disk C:\: $($metrics.DiskSpaceGB) GB free / $($metrics.DiskTotalGB) GB total ($($metrics.DiskUsedPercent)% used)

RECENT ACTIVITY:
════════════════════════════════════════════════════
"@
        
        # Ajouter logs au header
        $enrichedLogs = $logHeader + "`r`n" + $script:LogsBuffer
        if ($enrichedLogs.Length -gt 8000) {
            $enrichedLogs = $enrichedLogs.Substring(0, 8000) + "`r`n... (tronqué)"
        }
        
        # Données avec MÉTRIQUES NUMÉRIQUES
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            IPAddress = $metrics.IPAddress
            State = "ONLINE"
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = $script:Version
            CPUUsage = $metrics.CPUUsage  # Nombre, pas string
            MemoryUsage = $metrics.MemoryUsage  # Nombre
            DiskSpaceGB = $metrics.DiskSpaceGB  # Nombre
            Logs = $enrichedLogs
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Envoyer à SharePoint
        Write-Log "Envoi heartbeat avec métriques..." "DEBUG"
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Heartbeat envoyé avec succès (ID: $($response.d.Id))" "SUCCESS"
        
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

# Envoyer le heartbeat avec métriques
Send-Heartbeat

Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS AGENT v$($script:Version) TERMINÉ" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

exit 0