# ════════════════════════════════════════════════════════════════════
# ATLAS Agent v14.0 - MONITORING TEMPS RÉEL AVANCÉ
# ════════════════════════════════════════════════════════════════════
# - Métriques détaillées processus
# - Monitoring services critiques
# - Alertes automatiques
# - Historique performances
# ════════════════════════════════════════════════════════════════════

$script:Version = "14.0"
$hostname = $env:COMPUTERNAME
$atlasPath = "C:\SYAGA-ATLAS"

# Configuration SharePoint
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

# Buffer logs amélioré
$script:LogsBuffer = ""
$script:MaxBufferSize = 10000
$script:PerformanceHistory = @()

# ════════════════════════════════════════════════════════════════════
# MONITORING SERVICES CRITIQUES
# ════════════════════════════════════════════════════════════════════
function Get-CriticalServices {
    $criticalServices = @(
        "W3SVC",        # IIS
        "MSSQLSERVER",  # SQL Server
        "MSExchangeIS", # Exchange
        "vmms",         # Hyper-V
        "VeeamBackupSvc", # Veeam
        "Spooler",      # Print Spooler
        "DNS",          # DNS Server
        "DFSR"          # DFS Replication
    )
    
    $servicesStatus = @{}
    
    foreach ($serviceName in $criticalServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            $servicesStatus[$serviceName] = @{
                Status = $service.Status.ToString()
                DisplayName = $service.DisplayName
                StartType = $service.StartType.ToString()
            }
            
            if ($service.Status -ne "Running" -and $service.StartType -ne "Disabled") {
                Write-Log "⚠️ SERVICE CRITIQUE ARRÊTÉ: $($service.DisplayName)" "WARNING"
            }
        }
    }
    
    return $servicesStatus
}

# ════════════════════════════════════════════════════════════════════
# TOP PROCESSUS CONSOMMATEURS
# ════════════════════════════════════════════════════════════════════
function Get-TopProcesses {
    $topProcesses = Get-Process | 
        Sort-Object -Property WorkingSet64 -Descending | 
        Select-Object -First 5 | 
        ForEach-Object {
            @{
                Name = $_.ProcessName
                MemoryMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
                CPU = [math]::Round($_.CPU, 1)
            }
        }
    
    return $topProcesses
}

# ════════════════════════════════════════════════════════════════════
# MÉTRIQUES AVANCÉES v14.0
# ════════════════════════════════════════════════════════════════════
function Get-AdvancedMetrics {
    Write-Log "Collecte métriques avancées v14.0..." "DEBUG"
    
    $metrics = @{
        # Métriques de base
        CPUUsage = 0
        MemoryUsage = 0
        DiskSpaceGB = 0
        
        # Nouvelles métriques v14.0
        NetworkMbps = 0
        ActiveConnections = 0
        ProcessCount = 0
        ServicesStopped = 0
        EventLogErrors = 0
        Uptime = ""
    }
    
    try {
        # CPU avec moyenne sur 3 échantillons
        $cpuSamples = @()
        for ($i = 0; $i -lt 3; $i++) {
            $cpuCounter = Get-Counter '\Processeur(_Total)\% temps processeur' -ErrorAction SilentlyContinue
            if ($cpuCounter) {
                $cpuSamples += $cpuCounter.CounterSamples[0].CookedValue
                Start-Sleep -Milliseconds 500
            }
        }
        if ($cpuSamples.Count -gt 0) {
            $metrics.CPUUsage = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 1)
        }
        
        # Memory
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $memTotal = $os.TotalVisibleMemorySize
        $memFree = $os.FreePhysicalMemory
        $metrics.MemoryUsage = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)
        
        # Disk
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        $metrics.DiskSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        
        # Network
        $netAdapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        $metrics.ActiveConnections = (Get-NetTCPConnection | Where-Object {$_.State -eq "Established"}).Count
        
        # Process count
        $metrics.ProcessCount = (Get-Process).Count
        
        # Services stopped
        $allServices = Get-Service | Where-Object {$_.StartType -eq "Automatic"}
        $metrics.ServicesStopped = ($allServices | Where-Object {$_.Status -ne "Running"}).Count
        
        # Event log errors (dernière heure)
        $hourAgo = (Get-Date).AddHours(-1)
        $systemErrors = Get-EventLog -LogName System -EntryType Error -After $hourAgo -ErrorAction SilentlyContinue
        $metrics.EventLogErrors = if ($systemErrors) { $systemErrors.Count } else { 0 }
        
        # Uptime
        $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        $uptime = (Get-Date) - $bootTime
        $metrics.Uptime = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        
        Write-Log "Métriques avancées collectées: CPU=$($metrics.CPUUsage)% MEM=$($metrics.MemoryUsage)% Processes=$($metrics.ProcessCount) Errors=$($metrics.EventLogErrors)" "INFO"
        
    } catch {
        Write-Log "Erreur collecte métriques avancées: $_" "ERROR"
    }
    
    return $metrics
}

# ════════════════════════════════════════════════════════════════════
# ANALYSE PRÉDICTIVE
# ════════════════════════════════════════════════════════════════════
function Analyze-Trends {
    param($currentMetrics)
    
    # Ajouter à l'historique
    $script:PerformanceHistory += @{
        Timestamp = Get-Date
        CPU = $currentMetrics.CPUUsage
        Memory = $currentMetrics.MemoryUsage
        Disk = $currentMetrics.DiskSpaceGB
    }
    
    # Garder seulement les 10 dernières mesures
    if ($script:PerformanceHistory.Count -gt 10) {
        $script:PerformanceHistory = $script:PerformanceHistory[-10..-1]
    }
    
    # Analyser tendances
    $alerts = @()
    
    if ($currentMetrics.CPUUsage -gt 90) {
        $alerts += "🔴 CPU CRITIQUE: $($currentMetrics.CPUUsage)%"
    } elseif ($currentMetrics.CPUUsage -gt 75) {
        $alerts += "🟠 CPU ÉLEVÉ: $($currentMetrics.CPUUsage)%"
    }
    
    if ($currentMetrics.MemoryUsage -gt 90) {
        $alerts += "🔴 MÉMOIRE CRITIQUE: $($currentMetrics.MemoryUsage)%"
    } elseif ($currentMetrics.MemoryUsage -gt 80) {
        $alerts += "🟠 MÉMOIRE ÉLEVÉE: $($currentMetrics.MemoryUsage)%"
    }
    
    if ($currentMetrics.DiskSpaceGB -lt 10) {
        $alerts += "🔴 ESPACE DISQUE CRITIQUE: $($currentMetrics.DiskSpaceGB) GB"
    } elseif ($currentMetrics.DiskSpaceGB -lt 50) {
        $alerts += "🟠 ESPACE DISQUE BAS: $($currentMetrics.DiskSpaceGB) GB"
    }
    
    if ($currentMetrics.EventLogErrors -gt 50) {
        $alerts += "🔴 ERREURS SYSTÈME: $($currentMetrics.EventLogErrors) erreurs/heure"
    }
    
    if ($currentMetrics.ServicesStopped -gt 0) {
        $alerts += "⚠️ SERVICES ARRÊTÉS: $($currentMetrics.ServicesStopped)"
    }
    
    return $alerts
}

# ════════════════════════════════════════════════════════════════════
# FONCTION LOG AMÉLIORÉE
# ════════════════════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxBufferSize) {
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $script:MaxBufferSize)
    }
    
    # Codes couleur améliorés
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        "ALERT" { Write-Host $logEntry -ForegroundColor Red -BackgroundColor Yellow }
        "DEBUG" { Write-Host $logEntry -ForegroundColor DarkGray }
        default { Write-Host $logEntry }
    }
}

# ════════════════════════════════════════════════════════════════════
# HEARTBEAT v14.0 AVEC MONITORING COMPLET
# ════════════════════════════════════════════════════════════════════
function Send-Heartbeat {
    try {
        Write-Log "Préparation heartbeat v$($script:Version) avec monitoring avancé..." "DEBUG"
        
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
        
        # Collecter métriques avancées
        $metrics = Get-AdvancedMetrics
        $services = Get-CriticalServices
        $topProc = Get-TopProcesses
        $alerts = Analyze-Trends $metrics
        
        # IP
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        # Générer alertes dans les logs
        foreach ($alert in $alerts) {
            Write-Log $alert "ALERT"
        }
        
        # Créer rapport complet
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $servicesReport = ($services.GetEnumerator() | ForEach-Object {
            "  $($_.Key): $($_.Value.Status)"
        }) -join "`r`n"
        
        $processReport = ($topProc | ForEach-Object {
            "  $($_.Name): $($_.MemoryMB) MB"
        }) -join "`r`n"
        
        $alertsReport = if ($alerts.Count -gt 0) {
            "`r`n⚠️ ALERTES ACTIVES:`r`n" + ($alerts -join "`r`n")
        } else {
            "`r`n✅ Aucune alerte active"
        }
        
        $logHeader = @"
════════════════════════════════════════════════════
ATLAS v$($script:Version) - MONITORING TEMPS RÉEL
════════════════════════════════════════════════════
Hostname: $hostname ($ip)
Time: $currentTime
Uptime: $($metrics.Uptime)

MÉTRIQUES SYSTÈME:
  CPU: $($metrics.CPUUsage)%
  Mémoire: $($metrics.MemoryUsage)%  
  Disque C:\: $($metrics.DiskSpaceGB) GB libre
  Processus: $($metrics.ProcessCount)
  Connexions: $($metrics.ActiveConnections)
  Erreurs (1h): $($metrics.EventLogErrors)

SERVICES CRITIQUES:
$servicesReport

TOP PROCESSUS:
$processReport

$alertsReport

LOGS RÉCENTS:
════════════════════════════════════════════════════
"@
        
        # Ajouter logs
        $enrichedLogs = $logHeader + "`r`n" + $script:LogsBuffer
        if ($enrichedLogs.Length -gt 8000) {
            $enrichedLogs = $enrichedLogs.Substring(0, 8000) + "`r`n... (tronqué)"
        }
        
        # Déterminer état global
        $globalState = if ($alerts.Count -gt 0) {
            if ($alerts | Where-Object {$_ -match "🔴"}) {
                "CRITICAL"
            } else {
                "WARNING"
            }
        } else {
            "HEALTHY"
        }
        
        # Données SharePoint
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            IPAddress = $ip
            State = $globalState
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = $script:Version
            CPUUsage = $metrics.CPUUsage
            MemoryUsage = $metrics.MemoryUsage
            DiskSpaceGB = $metrics.DiskSpaceGB
            Logs = $enrichedLogs
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Envoyer à SharePoint
        Write-Log "Envoi monitoring complet..." "DEBUG"
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Monitoring v14.0 envoyé (État: $globalState)" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════
Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS v$($script:Version) - MONITORING TEMPS RÉEL" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

# Envoyer heartbeat avec monitoring complet
Send-Heartbeat

Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS v$($script:Version) TERMINÉ" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

exit 0