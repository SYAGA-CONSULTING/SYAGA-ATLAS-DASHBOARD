# REPARATION IMMEDIATE - Supprime l'ancienne entree et recree proprement

Write-Host ""
Write-Host "=== REPARATION SHAREPOINT ===" -ForegroundColor Yellow
Write-Host ""

$configFile = "C:\ATLAS\config.json"

if (!(Test-Path $configFile)) {
    Write-Host "[ERREUR] Pas de config!" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configFile -Raw | ConvertFrom-Json

# Obtenir token
$body = @{
    client_id = $config.ClientId
    scope = "https://graph.microsoft.com/.default"
    client_secret = $config.ClientSecret
    grant_type = "client_credentials"
}

$tokenUrl = "https://login.microsoftonline.com/$($config.TenantId)/oauth2/v2.0/token"
$response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType "application/x-www-form-urlencoded"

if (!$response.access_token) {
    Write-Host "[ERREUR] Pas de token!" -ForegroundColor Red
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $($response.access_token)"
    "Content-Type" = "application/json"
}

Write-Host "[1] Recherche de l'ancienne entree..." -ForegroundColor Cyan

$listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$expand=fields"

$items = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get

$oldItem = $null
foreach ($item in $items.value) {
    if ($item.fields.Title -eq $env:COMPUTERNAME -or $item.fields.Hostname -eq $env:COMPUTERNAME) {
        $oldItem = $item
        Write-Host "  Trouve: ID=$($item.id), Version=$($item.fields.AgentVersion)" -ForegroundColor Yellow
        break
    }
}

if ($oldItem) {
    Write-Host "[2] Suppression de l'ancienne entree..." -ForegroundColor Cyan
    
    $deleteUrl = "$listUrl($($oldItem.id))"
    try {
        Invoke-RestMethod -Uri $deleteUrl -Headers $headers -Method DELETE
        Write-Host "  [OK] Ancienne entree supprimee" -ForegroundColor Green
    } catch {
        Write-Host "  [ERREUR] Suppression: $_" -ForegroundColor Red
    }
    
    Start-Sleep -Seconds 2
}

Write-Host "[3] Creation d'une nouvelle entree propre..." -ForegroundColor Cyan

# Creer nouvelle entree avec les bons types
$newFields = @{
    "Title" = [string]$env:COMPUTERNAME
    "Hostname" = [string]$env:COMPUTERNAME
    "IPAddress" = [string]"0.0.0.0"
    "State" = [string]"OK"
    "CPUUsage" = [double]5.0
    "MemoryUsage" = [double]50.0
    "DiskSpaceGB" = [double]100.0
    "Role" = [string]"Server"
    "HyperVStatus" = [string]"N/A"
    "VeeamStatus" = [string]"N/A"
    "LastContact" = [string](Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    "AgentVersion" = [string]"5.6-FINAL"
    "PendingUpdates" = [double]0
}

$body = @{ fields = $newFields } | ConvertTo-Json -Depth 10

try {
    $createUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
    
    $newItem = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $body
    Write-Host "  [OK] Nouvelle entree creee avec ID: $($newItem.id)" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] Creation: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4] Redemarrage de l'agent..." -ForegroundColor Cyan

Restart-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== REPARATION TERMINEE ===" -ForegroundColor Green
Write-Host ""
Write-Host "L'agent devrait maintenant fonctionner sans erreur 400!" -ForegroundColor Green
Write-Host "Attendez 3 minutes et verifiez le dashboard." -ForegroundColor Yellow