# Migration des données ATLAS vers SharePoint
# Date: 2025-08-28

param(
    [string]$SiteUrl = "https://syaga.sharepoint.com/sites/ATLAS",
    [string]$ListName = "ATLAS-Servers"
)

# Configuration
$JsonPath = "/home/sq/SYAGA-CONSULTING/SYAGA-ATLAS-DATA/servers.json"

# Connexion SharePoint
Write-Host "🔐 Connexion à SharePoint..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -Interactive

# Charger les données JSON
Write-Host "📂 Chargement des données depuis $JsonPath..." -ForegroundColor Cyan
$jsonContent = Get-Content $JsonPath -Raw
$data = $jsonContent | ConvertFrom-Json

Write-Host "📊 Trouvé $($data.servers.Count) serveurs à migrer" -ForegroundColor Green

# Migrer chaque serveur
foreach ($server in $data.servers) {
    Write-Host "`n🖥️ Migration de $($server.hostname)..." -ForegroundColor Yellow
    
    # Vérifier si le serveur existe déjà
    $existingItem = Get-PnPListItem -List $ListName -Query "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$($server.hostname)</Value></Eq></Where></Query></View>"
    
    $itemValues = @{
        "Title" = $server.hostname
        "Hostname" = $server.hostname
        "IPAddress" = $server.ip
        "Role" = $server.role
        "OperatingSystem" = $server.os
        "State" = $server.state
        "PendingUpdates" = $server.pendingUpdates
        "InstalledUpdates" = $server.installedUpdates
        "FailedUpdates" = $server.failedUpdates
        "RebootRequired" = $server.rebootRequired
        "HyperVStatus" = $server.hypervStatus
        "VeeamStatus" = $server.veeamStatus
        "CPUUsage" = $server.cpuUsage
        "MemoryUsage" = $server.memoryUsage
        "DiskSpaceGB" = $server.diskSpaceGB
        "AgentInstalled" = $server.agentInstalled
        "AgentVersion" = $server.agentVersion
    }
    
    # Ajouter LastContact si présent
    if ($server.lastContact) {
        $itemValues["LastContact"] = [DateTime]::Parse($server.lastContact)
    }
    
    # Ajouter LastUpdate
    $itemValues["LastUpdate"] = [DateTime]::UtcNow
    
    if ($existingItem) {
        # Mettre à jour
        Write-Host "  📝 Mise à jour de l'enregistrement existant..." -ForegroundColor Blue
        Set-PnPListItem -List $ListName -Identity $existingItem.Id -Values $itemValues
    } else {
        # Créer nouveau
        Write-Host "  ➕ Création d'un nouvel enregistrement..." -ForegroundColor Green
        Add-PnPListItem -List $ListName -Values $itemValues
    }
    
    Write-Host "  ✅ $($server.hostname) migré avec succès!" -ForegroundColor Green
}

Write-Host "`n🎉 MIGRATION TERMINÉE!" -ForegroundColor Green
Write-Host "📊 $($data.servers.Count) serveurs migrés vers SharePoint" -ForegroundColor Cyan
Write-Host "🔗 Accéder à la liste: $SiteUrl/Lists/$ListName" -ForegroundColor Cyan

# Afficher un résumé
$items = Get-PnPListItem -List $ListName
Write-Host "`n📈 RÉSUMÉ DE LA LISTE SHAREPOINT:" -ForegroundColor Yellow
Write-Host "  • Total serveurs: $($items.Count)" -ForegroundColor White
Write-Host "  • Serveurs OK: $(($items | Where-Object {$_["State"] -eq "OK"}).Count)" -ForegroundColor Green
Write-Host "  • Agents installés: $(($items | Where-Object {$_["AgentInstalled"] -eq $true}).Count)" -ForegroundColor Blue
Write-Host "  • Mises à jour en attente: $(($items | ForEach-Object {$_["PendingUpdates"]} | Measure-Object -Sum).Sum)" -ForegroundColor Yellow