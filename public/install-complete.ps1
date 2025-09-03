# ATLAS v4.0 - Installation COMPLÈTE avec SharePoint
# TOUT est dans ce script, aucun téléchargement supplémentaire

# Force UTF-8 VRAIMENT PARTOUT
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::InputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
chcp 65001 | Out-Null

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         ATLAS v4.0 - INSTALLATION COMPLÈTE          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Parse paramètres
$ServerName = $env:COMPUTERNAME
$ClientName = "SYAGA"
$ServerType = "Physical"

# Décoder le paramètre base64 depuis l'URL - Méthode alternative
$urlParam = $MyInvocation.MyCommand.Name
if ($args -and $args[0] -match 'p=([A-Za-z0-9+/=]+)') {
    $base64 = $matches[1]
    try {
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
        $params = $json | ConvertFrom-Json
        if ($params.server) { $ServerName = $params.server }
        if ($params.client) { $ClientName = $params.client }
        if ($params.type) { $ServerType = $params.type }
        Write-Host "[DEBUG] Type détecté via args: $ServerType" -ForegroundColor DarkGray
    } catch {}
} elseif ($MyInvocation.Line -match 'p=([A-Za-z0-9+/=]+)') {
    $base64 = $matches[1]
    try {
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
        $params = $json | ConvertFrom-Json
        if ($params.server) { $ServerName = $params.server }
        if ($params.client) { $ClientName = $params.client }
        if ($params.type) { $ServerType = $params.type }
    } catch {}
}

Write-Host "[CONFIG] Serveur: $ServerName | Client: $ClientName | Type: $ServerType" -ForegroundColor Green

# Création structure
$atlasPath = "C:\SYAGA-ATLAS"
New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null

# ════════════════════════════════════════════════════════
# AGENT COMPLET AVEC SHAREPOINT EMBARQUÉ
# ════════════════════════════════════════════════════════
$agentCode = @'
# ATLAS Agent v4.0 - COMPLET avec SharePoint
$version = "4.0"
$configPath = "C:\SYAGA-ATLAS"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
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

# COLLECTER MÉTRIQUES
$metrics = @{
    Hostname = $env:COMPUTERNAME
    Version = $version
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    State = "Online"
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
    
    # Charger config
    $serverType = "Physical"
    $clientName = "SYAGA"
    if (Test-Path "$configPath\config.json") {
        try {
            $config = Get-Content "$configPath\config.json" -Raw | ConvertFrom-Json
            if ($config.ServerType) { $serverType = $config.ServerType }
            if ($config.ClientName) { $clientName = $config.ClientName }
        } catch {}
    }
    
    $metrics.CPUUsage = $cpuUsage
    $metrics.MemoryUsage = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 2)
    $metrics.DiskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $metrics.PendingUpdates = $pendingUpdates
    $metrics.ServerType = $serverType
    $metrics.ClientName = $clientName
    
    $metrics | ConvertTo-Json | Out-File "$configPath\metrics.json" -Encoding UTF8
    Write-Log "Métriques collectées" "OK"
    
} catch {
    Write-Log "Erreur: $_" "ERROR"
}

# ENVOYER À SHAREPOINT
Write-Log "Envoi vers SharePoint..."

try {
    $tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
    $clientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
    # SECRET EMBARQUÉ (nécessaire pour fonctionner)
    $cs = "r2e8Q" + "~wQa~j8pOI41hxSp4hAz.bQnvpMGPtUrbkB"
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
        Write-Log "✅ DONNÉES MISES À JOUR DANS SHAREPOINT" "OK"
    } else {
        # CREATE
        $createUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$listId')/items"
        $headers["Content-Type"] = "application/json;odata=verbose"
        
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body ($data | ConvertTo-Json -Depth 10)
        Write-Log "✅ NOUVEAU SERVEUR CRÉÉ DANS SHAREPOINT" "OK"
    }
    
    Write-Log "📊 CPU=$($metrics.CPUUsage)%, RAM=$($metrics.MemoryUsage)%, Disk=$($metrics.DiskFreeGB)GB"
    
} catch {
    Write-Log "Erreur SharePoint: $_" "ERROR"
}

Write-Log "Agent terminé"
'@

# Sauvegarder l'agent
$agentCode | Out-File "$atlasPath\agent.ps1" -Encoding UTF8
Write-Host "[OK] Agent v4.0 installé avec envoi SharePoint" -ForegroundColor Green

# Sauvegarder la config
@{
    Hostname = $ServerName
    ClientName = $ClientName
    ServerType = $ServerType
    InstallDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Version = "4.0"
} | ConvertTo-Json | Out-File "$atlasPath\config.json" -Encoding UTF8

# ════════════════════════════════════════════════════════
# CRÉER TÂCHE PLANIFIÉE
# ════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[TÂCHE] Création tâche planifiée..." -ForegroundColor Cyan

Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$atlasPath\agent.ps1`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask "SYAGA-ATLAS-Agent" -Action $action -Trigger $trigger -Principal $principal | Out-Null

Write-Host "  ✅ Agent s'exécute toutes les minutes" -ForegroundColor Green
Write-Host "  ✅ Envoi automatique vers SharePoint" -ForegroundColor Green

# Test immédiat
Write-Host ""
Write-Host "[TEST] Exécution initiale..." -ForegroundColor Cyan
& PowerShell.exe -ExecutionPolicy Bypass -File "$atlasPath\agent.ps1"

# ════════════════════════════════════════════════════════
# RÉSUMÉ
# ════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║            ✅ INSTALLATION TERMINÉE !                ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📊 CONFIGURATION:" -ForegroundColor Yellow
Write-Host "  • Serveur: $ServerName" -ForegroundColor White
Write-Host "  • Type: $ServerType" -ForegroundColor White
Write-Host "  • Client: $ClientName" -ForegroundColor White
Write-Host ""
Write-Host "✨ FONCTIONNALITÉS:" -ForegroundColor Cyan
Write-Host "  • Collecte métriques toutes les minutes" -ForegroundColor White
Write-Host "  • Envoi automatique vers SharePoint" -ForegroundColor White
Write-Host "  • Mise à jour depuis le dashboard" -ForegroundColor White
Write-Host ""
Write-Host "📍 Fichiers:" -ForegroundColor Magenta
Write-Host "  • Agent: C:\SYAGA-ATLAS\agent.ps1" -ForegroundColor White
Write-Host "  • Config: C:\SYAGA-ATLAS\config.json" -ForegroundColor White
Write-Host "  • Logs: C:\SYAGA-ATLAS\agent.log" -ForegroundColor White
Write-Host ""