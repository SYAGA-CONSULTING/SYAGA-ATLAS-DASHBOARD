# ATLAS Agent v5.4 - Enhanced Auto-Update
$version = "5.4"
$configPath = "C:\SYAGA-ATLAS"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param($Message, $Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$ts] [$Level] $Message"
    if (!(Test-Path $configPath)) {
        New-Item -ItemType Directory -Path $configPath -Force | Out-Null
    }
    Add-Content "$configPath\agent.log" -Value $log -Encoding UTF8
    $color = @{INFO="White"; OK="Green"; ERROR="Red"; UPDATE="Cyan"; WARNING="Yellow"; v53="Magenta"; v54="Cyan"}[$Level]
    Write-Host $log -ForegroundColor $color
}

Write-Log "===== Agent ATLAS v$version DEMARRE =====" "v54"

# FONCTION AUTO-UPDATE v5.4 - Améliorée avec logs détaillés
function Check-Update {
    Write-Log "Check auto-update v5.4 - Recherche commandes..." "UPDATE"
    
    try {
        $tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        $clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
        $cs = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
        
        # OAuth
        $body = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $cs
            resource = "00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -ContentType "application/x-www-form-urlencoded" -Body $body -EA Stop
        
        $token = $tokenResponse.access_token
        
        # Chercher commandes UPDATE
        $hostname = $env:COMPUTERNAME
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        $items = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        
        # Chercher UPDATE_COMMAND ou UPDATE_ALL
        foreach ($item in $items.d.results) {
            if ($item.Title -eq "UPDATE_COMMAND_$hostname" -or $item.Title -eq "UPDATE_ALL") {
                Write-Log ">>> UPDATE DETECTE: $($item.Title) <<<" "v54"
                
                # Obtenir version cible depuis AgentVersion du command
                $targetVersion = if ($item.AgentVersion) { $item.AgentVersion } else { "5.3" }
                Write-Log "Version cible: v$targetVersion" "UPDATE"
                
                # Télécharger nouvelle version
                $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$targetVersion.ps1"
                Write-Log "Download: $newAgentUrl" "UPDATE"
                
                try {
                    $newAgent = Invoke-RestMethod -Uri $newAgentUrl -EA Stop
                    
                    # Sauvegarder ancien agent
                    if (Test-Path "$configPath\agent.ps1") {
                        Copy-Item "$configPath\agent.ps1" "$configPath\agent.backup.ps1" -Force
                    }
                    
                    # Installer nouveau
                    $newAgent | Out-File "$configPath\agent.ps1" -Encoding UTF8 -Force
                    Write-Log "!!! AGENT MIS A JOUR VERS v$targetVersion !!!" "v54"
                    
                    # Supprimer la commande UPDATE
                    $deleteUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items($($item.Id))"
                    $headers["IF-MATCH"] = "*"
                    $headers["X-HTTP-Method"] = "DELETE"
                    Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method POST
                    Write-Log "Commande supprimee" "OK"
                    
                    # Logger la mise à jour
                    $updateLog = @{
                        __metadata = @{ type = "SP.Data.ATLASServersListItem" }
                        Title = "LOG_UPDATE_$hostname"
                        Hostname = $hostname
                        State = "UPDATE_SUCCESS"
                        AgentVersion = $targetVersion
                        Role = "Log"
                        VeeamStatus = "UPDATE SUCCESS: v$version -> v$targetVersion @ $(Get-Date -Format 'HH:mm:ss')"
                        LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                    }
                    
                    $headers = @{
                        "Authorization" = "Bearer $token"
                        "Accept" = "application/json;odata=verbose"
                        "Content-Type" = "application/json;odata=verbose"
                    }
                    
                    $createUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
                    Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body ($updateLog | ConvertTo-Json -Depth 10)
                    
                    # Redémarrer
                    Write-Log "Redemarrage..." "UPDATE"
                    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -EA SilentlyContinue
                    exit 0
                    
                } catch {
                    Write-Log "Erreur download: $_" "ERROR"
                }
            }
        }
        
    } catch {
        Write-Log "Erreur update check: $_" "WARNING"
    }
}

# CHARGER CONFIG
$serverType = "Physical"
$clientName = "SYAGA"
if (Test-Path "$configPath\config.json") {
    try {
        $config = Get-Content "$configPath\config.json" -Raw | ConvertFrom-Json
        if ($config.ServerType) { 
            $serverType = $config.ServerType
            Write-Log "Config: Type=$serverType" "v53"
        }
        if ($config.ClientName) { $clientName = $config.ClientName }
    } catch {
        Write-Log "Erreur config: $_" "WARNING"
    }
}

# CHECK UPDATE EN PREMIER (v5.3)
Check-Update

# COLLECTER METRIQUES
$metrics = @{
    Hostname = $env:COMPUTERNAME
    Version = $version
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    State = "Online"
    ServerType = $serverType
    ClientName = $clientName
}

try {
    Write-Log "Collecte metriques v5.3..."
    
    $os = Get-CimInstance Win32_OperatingSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    
    # v5.3: Détection étendue
    $services = @{
        SQL = (Get-Service -Name "MSSQLSERVER" -EA SilentlyContinue).Status -eq "Running"
        Veeam = (Get-Service -Name "Veeam*" -EA SilentlyContinue | Where-Object {$_.Status -eq "Running"}).Count -gt 0
        HyperV = (Get-Service -Name "vmms" -EA SilentlyContinue).Status -eq "Running"
        IIS = (Get-Service -Name "W3SVC" -EA SilentlyContinue).Status -eq "Running"
        Exchange = (Get-Service -Name "MSExchange*" -EA SilentlyContinue | Where-Object {$_.Status -eq "Running"}).Count -gt 0
    }
    
    $cpuUsage = 0
    try {
        $counter = Get-Counter "\Processeur(_Total)\% temps processeur" -EA SilentlyContinue
        if ($counter) { $cpuUsage = [math]::Round($counter.CounterSamples[0].CookedValue, 2) }
    } catch {}
    
    $pendingUpdates = 0
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0")
        $pendingUpdates = $result.Updates.Count
    } catch {}
    
    # v5.3: Uptime
    $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptimeDays = [math]::Round($uptime.TotalDays, 1)
    
    $metrics.CPUUsage = $cpuUsage
    $metrics.MemoryUsage = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 2)
    $metrics.DiskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $metrics.PendingUpdates = $pendingUpdates
    $metrics.Services = $services
    $metrics.UptimeDays = $uptimeDays
    
    $metrics | ConvertTo-Json | Out-File "$configPath\metrics.json" -Encoding UTF8
    Write-Log "Metriques OK - Uptime: $uptimeDays jours" "v53"
    
} catch {
    Write-Log "Erreur metriques: $_" "ERROR"
}

# ENVOYER A SHAREPOINT
Write-Log "Envoi SharePoint (v5.3)..."

try {
    $tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
    $clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
    $cs = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
    $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
    
    # OAuth
    $body = @{
        grant_type = "client_credentials"
        client_id = "$clientId@$tenantId"
        client_secret = $cs
        resource = "00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@$tenantId"
    }
    
    $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
        -Method POST -ContentType "application/x-www-form-urlencoded" -Body $body
    
    $token = $tokenResponse.access_token
    Write-Log "Token OK" "OK"
    
    # Chercher serveur existant
    $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Accept" = "application/json;odata=verbose"
    }
    
    $search = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
    
    $existingItem = $null
    foreach ($item in $search.d.results) {
        if ($item.Hostname -eq $metrics.Hostname -or $item.Title -eq $metrics.Hostname) {
            $existingItem = $item
            break
        }
    }
    
    # v5.3: Status enrichi avec tous les services
    $statusParts = @("v$version")
    if ($metrics.UptimeDays) { $statusParts += "Up:$($metrics.UptimeDays)d" }
    if ($metrics.Services.SQL) { $statusParts += "SQL" }
    if ($metrics.Services.Veeam) { $statusParts += "Veeam" }
    if ($metrics.Services.IIS) { $statusParts += "IIS" }
    if ($metrics.Services.Exchange) { $statusParts += "Exchange" }
    $statusText = $statusParts -join " | "
    
    $data = @{
        __metadata = @{ type = "SP.Data.ATLASServersListItem" }
        Title = $metrics.Hostname
        Hostname = $metrics.Hostname
        State = $metrics.State
        CPUUsage = [double]$metrics.CPUUsage
        MemoryUsage = [double]$metrics.MemoryUsage
        DiskSpaceGB = [double]$metrics.DiskFreeGB
        PendingUpdates = [int]$metrics.PendingUpdates
        LastContact = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        AgentVersion = $metrics.Version
        Role = $metrics.ServerType
        VeeamStatus = $statusText
        HyperVStatus = if ($metrics.Services.HyperV) { "Active" } elseif ($serverType -eq "Host") { "Stopped" } else { "N/A" }
    }
    
    if ($existingItem) {
        # UPDATE
        $id = $existingItem.Id
        Write-Log "Update ID: $id" "INFO"
        $updateUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items($id)"
        $headers["Content-Type"] = "application/json;odata=verbose"
        $headers["IF-MATCH"] = "*"
        $headers["X-HTTP-Method"] = "MERGE"
        
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method POST -Body ($data | ConvertTo-Json -Depth 10)
        Write-Log "[v5.3] UPDATE OK - $statusText" "v53"
    } else {
        # CREATE
        $createUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
        $headers["Content-Type"] = "application/json;odata=verbose"
        
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body ($data | ConvertTo-Json -Depth 10)
        Write-Log "[v5.3] CREATE OK - $statusText" "v53"
    }
    
    Write-Log "CPU:$($metrics.CPUUsage)% RAM:$($metrics.MemoryUsage)% Disk:$($metrics.DiskFreeGB)GB Up:$($metrics.UptimeDays)d"
    
} catch {
    Write-Log "Erreur SharePoint: $_" "ERROR"
}

Write-Log "===== Agent v$version TERMINE =====" "v53"