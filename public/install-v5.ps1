# ATLAS v5.0 - Installation FINALE qui FONCTIONNE

# FORCE UTF-8 - Compatible toutes versions
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null 2>$null

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "         ATLAS v5.0 - INSTALLATION FINALE" -ForegroundColor Cyan  
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# Parse paramètres depuis variable d'environnement
$ServerName = $env:COMPUTERNAME
$ClientName = "SYAGA"
$ServerType = "Physical"

# Lire le parametre depuis la variable d'environnement
$p = $env:ATLAS_PARAMS

if ($p) {
    Write-Host "[INFO] Parametres recus via variable d'environnement" -ForegroundColor Green
    try {
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($p))
        Write-Host "[DEBUG] JSON decode: $json" -ForegroundColor DarkGray
        $params = $json | ConvertFrom-Json
        if ($params.server) { $ServerName = $params.server }
        if ($params.client) { $ClientName = $params.client }
        if ($params.type) { 
            $ServerType = $params.type
            Write-Host "[INFO] Type detecte: $ServerType" -ForegroundColor Green
        }
    } catch {
        Write-Host "[ERROR] Erreur decodage: $_" -ForegroundColor Red
    }
} else {
    Write-Host "[WARNING] Aucun parametre trouve - utilisation des valeurs par defaut" -ForegroundColor Yellow
}

Write-Host "[CONFIG] Serveur: $ServerName | Client: $ClientName | Type: $ServerType" -ForegroundColor Green

# Créer structure
$atlasPath = "C:\SYAGA-ATLAS"
New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null

# Sauvegarder config IMMÉDIATEMENT avec le BON type
@{
    Hostname = $ServerName
    ClientName = $ClientName
    ServerType = $ServerType
    InstallDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Version = "5.0"
} | ConvertTo-Json | Out-File "$atlasPath\config.json" -Encoding UTF8

Write-Host "[OK] Configuration sauvegardee avec Type: $ServerType" -ForegroundColor Green

# AGENT v5.0 AVEC SHAREPOINT
$agentCode = @'
# ATLAS Agent v5.0
$version = "5.0"
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

Write-Log "Agent ATLAS v$version démarré"

# CHARGER CONFIG EN PREMIER
$serverType = "Physical"
$clientName = "SYAGA"
if (Test-Path "$configPath\config.json") {
    try {
        $config = Get-Content "$configPath\config.json" -Raw | ConvertFrom-Json
        if ($config.ServerType) { 
            $serverType = $config.ServerType
            Write-Log "Type chargé depuis config: $serverType"
        }
        if ($config.ClientName) { $clientName = $config.ClientName }
    } catch {
        Write-Log "Erreur lecture config: $_" "WARNING"
    }
}

# COLLECTER MÉTRIQUES
$metrics = @{
    Hostname = $env:COMPUTERNAME
    Version = $version
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    State = "Online"
    ServerType = $serverType
    ClientName = $clientName
}

try {
    Write-Log "Collecte des métriques..."
    
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
    Write-Log "Métriques collectées - Type: $serverType" "OK"
    
} catch {
    Write-Log "Erreur: $_" "ERROR"
}

# ENVOYER À SHAREPOINT
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
    
    # Chercher si existe
    $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items?`$filter=Hostname eq '$($metrics.Hostname)'"
    $headers = @{
        "Authorization" = "Bearer $token"
        "Accept" = "application/json;odata=verbose"
    }
    
    $search = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
    
    # Données
    $data = @{
        __metadata = @{ type = "SP.Data.ATLAS_x002d_ServersListItem" }
        Title = $metrics.Hostname
        Hostname = $metrics.Hostname
        State = $metrics.State
        CPUUsage = [double]$metrics.CPUUsage
        MemoryUsage = [double]$metrics.MemoryUsage
        DiskSpaceGB = [double]$metrics.DiskFreeGB
        PendingUpdates = [int]$metrics.PendingUpdates
        LastUpdate = (Get-Date).ToString("yyyy-MM-dd")
        AgentVersion = $metrics.Version
        ServerType = $metrics.ServerType
        ClientName = $metrics.ClientName
    }
    
    if ($search.d.results.Count -gt 0) {
        # UPDATE
        $id = $search.d.results[0].Id
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

Write-Log "Agent terminé"
'@

# Sauvegarder agent
$agentCode | Out-File "$atlasPath\agent.ps1" -Encoding UTF8
Write-Host "[OK] Agent v5.0 installe" -ForegroundColor Green

# CRÉER TÂCHE
Write-Host ""
Write-Host "[TACHE] Creation tache planifiee..." -ForegroundColor Cyan

Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$atlasPath\agent.ps1`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask "SYAGA-ATLAS-Agent" -Action $action -Trigger $trigger -Principal $principal | Out-Null

Write-Host "  [OK] Agent s'execute toutes les minutes" -ForegroundColor Green

# Test
Write-Host ""
Write-Host "[TEST] Execution initiale..." -ForegroundColor Cyan
& PowerShell.exe -ExecutionPolicy Bypass -File "$atlasPath\agent.ps1"

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host "              [OK] INSTALLATION REUSSIE !" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration finale:" -ForegroundColor Yellow
Write-Host "  - Serveur: $ServerName" -ForegroundColor White
Write-Host "  - Type: $ServerType" -ForegroundColor White
Write-Host "  - Client: $ClientName" -ForegroundColor White
Write-Host ""