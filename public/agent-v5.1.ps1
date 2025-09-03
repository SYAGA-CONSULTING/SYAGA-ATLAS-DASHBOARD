# ATLAS Agent v5.1 - Avec Auto-Update
$version = "5.1"
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
    $color = @{INFO="White"; OK="Green"; ERROR="Red"; UPDATE="Cyan"; WARNING="Yellow"}[$Level]
    Write-Host $log -ForegroundColor $color
}

Write-Log "Agent ATLAS v$version demarre"

# FONCTION AUTO-UPDATE
function Check-Update {
    Write-Log "Verification mise a jour..." "UPDATE"
    
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
            -Method POST -ContentType "application/x-www-form-urlencoded" -Body $body
        
        $token = $tokenResponse.access_token
        
        # Chercher une commande UPDATE pour ce serveur
        $hostname = $env:COMPUTERNAME
        $listId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        $items = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        
        # Chercher item UPDATE_COMMAND
        foreach ($item in $items.d.results) {
            if ($item.Title -eq "UPDATE_COMMAND_$hostname" -or $item.Title -eq "UPDATE_ALL") {
                Write-Log "COMMANDE UPDATE DETECTEE!" "UPDATE"
                
                # Telecharger nouvelle version
                $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v5.3.ps1"
                Write-Log "Telechargement v5.3..." "UPDATE"
                
                $newAgent = Invoke-RestMethod -Uri $newAgentUrl
                $newAgent | Out-File "$configPath\agent.ps1" -Encoding UTF8 -Force
                
                Write-Log "Agent mis a jour vers v5.3!" "OK"
                
                # Supprimer la commande
                $deleteUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items($($item.Id))"
                $headers["IF-MATCH"] = "*"
                $headers["X-HTTP-Method"] = "DELETE"
                Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method POST
                
                Write-Log "Commande update supprimee" "OK"
                
                # Redemarrer l'agent
                Write-Log "Redemarrage de l'agent..." "UPDATE"
                exit 0
            }
        }
        
    } catch {
        Write-Log "Erreur check update: $_" "WARNING"
    }
}

# CHARGER CONFIG EN PREMIER
$serverType = "Physical"
$clientName = "SYAGA"
if (Test-Path "$configPath\config.json") {
    try {
        $config = Get-Content "$configPath\config.json" -Raw | ConvertFrom-Json
        if ($config.ServerType) { 
            $serverType = $config.ServerType
            Write-Log "Type charge depuis config: $serverType"
        }
        if ($config.ClientName) { $clientName = $config.ClientName }
    } catch {
        Write-Log "Erreur lecture config: $_" "WARNING"
    }
}

# VERIFIER UPDATE (v5.1 uniquement)
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
    Write-Log "Collecte des metriques..."
    
    $os = Get-CimInstance Win32_OperatingSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    
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
    
    $metrics.CPUUsage = $cpuUsage
    $metrics.MemoryUsage = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 2)
    $metrics.DiskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $metrics.PendingUpdates = $pendingUpdates
    
    $metrics | ConvertTo-Json | Out-File "$configPath\metrics.json" -Encoding UTF8
    Write-Log "Metriques collectees - Type: $serverType" "OK"
    
} catch {
    Write-Log "Erreur: $_" "ERROR"
}

# ENVOYER A SHAREPOINT
Write-Log "Envoi vers SharePoint..."

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
    Write-Log "Token obtenu" "OK"
    
    # Chercher si existe (avec un filtre qui fonctionne vraiment)
    $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Accept" = "application/json;odata=verbose"
    }
    
    $search = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
    
    # Filtrer localement pour trouver notre serveur
    $existingItem = $null
    foreach ($item in $search.d.results) {
        if ($item.Hostname -eq $metrics.Hostname -or $item.Title -eq $metrics.Hostname) {
            $existingItem = $item
            break
        }
    }
    
    # Donnees (avec les vrais champs SharePoint)
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
        Role = $metrics.ServerType  # Utiliser Role pour le type
        VeeamStatus = "OK"
        HyperVStatus = if ($metrics.ServerType -eq "Host") { "Active" } else { "N/A" }
    }
    
    if ($existingItem) {
        # UPDATE - Un item existe deja pour ce serveur
        $id = $existingItem.Id
        Write-Log "Item existant trouve avec ID: $id" "INFO"
        $updateUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items($id)"
        $headers["Content-Type"] = "application/json;odata=verbose"
        $headers["IF-MATCH"] = "*"
        $headers["X-HTTP-Method"] = "MERGE"
        
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method POST -Body ($data | ConvertTo-Json -Depth 10)
        Write-Log "[OK] DONNEES MISES A JOUR DANS SHAREPOINT (Type: $($metrics.ServerType))" "OK"
    } else {
        # CREATE
        $createUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
        $headers["Content-Type"] = "application/json;odata=verbose"
        
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body ($data | ConvertTo-Json -Depth 10)
        Write-Log "[OK] NOUVEAU SERVEUR CREE DANS SHAREPOINT (Type: $($metrics.ServerType))" "OK"
    }
    
    Write-Log "Stats: CPU=$($metrics.CPUUsage)%, RAM=$($metrics.MemoryUsage)%, Disk=$($metrics.DiskFreeGB)GB, Type=$($metrics.ServerType)"
    
} catch {
    Write-Log "Erreur SharePoint: $_" "ERROR"
}

Write-Log "Agent v$version termine"