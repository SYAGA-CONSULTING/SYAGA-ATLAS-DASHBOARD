# VERIFICATION DU SUCCES

Write-Host ""
Write-Host "=== VERIFICATION ===" -ForegroundColor Cyan
Write-Host ""

# Redemarrer la tache (compatible toutes versions Windows)
Write-Host "[1] Redemarrage de l'agent..." -ForegroundColor Yellow
Stop-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
Write-Host "  [OK] Agent redemarre" -ForegroundColor Green

Start-Sleep -Seconds 5

# Verifier les logs
Write-Host ""
Write-Host "[2] Derniers logs:" -ForegroundColor Yellow
$logFile = "C:\ATLAS\Logs\Agent-$(Get-Date -Format 'yyyyMMdd').log"
if (Test-Path $logFile) {
    Get-Content $logFile -Tail 10 | ForEach-Object {
        if ($_ -match "ERREUR.*400") {
            Write-Host "  $_" -ForegroundColor Red
        } elseif ($_ -match "SUCCES.*Metriques") {
            Write-Host "  $_" -ForegroundColor Green
        } elseif ($_ -match "UPDATE") {
            Write-Host "  $_" -ForegroundColor Cyan
        } else {
            Write-Host "  $_" -ForegroundColor Gray
        }
    }
}

Write-Host ""
Write-Host "[3] Test SharePoint:" -ForegroundColor Yellow

$configFile = "C:\ATLAS\config.json"
$config = Get-Content $configFile -Raw | ConvertFrom-Json

$body = @{
    client_id = $config.ClientId
    scope = "https://graph.microsoft.com/.default"
    client_secret = $config.ClientSecret
    grant_type = "client_credentials"
}

$tokenUrl = "https://login.microsoftonline.com/$($config.TenantId)/oauth2/v2.0/token"
$response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType "application/x-www-form-urlencoded"

$headers = @{
    "Authorization" = "Bearer $($response.access_token)"
    "Accept" = "application/json"
}

$listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$expand=fields"

$items = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get

$count = 0
foreach ($item in $items.value) {
    if ($item.fields.Title -eq $env:COMPUTERNAME -or $item.fields.Hostname -eq $env:COMPUTERNAME) {
        $count++
        Write-Host "  Entree $count - ID=$($item.id), Version=$($item.fields.AgentVersion), Contact=$($item.fields.LastContact)" -ForegroundColor $(if($item.fields.AgentVersion -eq "5.6-FINAL"){"Green"}else{"Yellow"})
    }
}

Write-Host ""
if ($count -gt 1) {
    Write-Host "[!] ATTENTION: $count entrees pour ce serveur (normal temporairement)" -ForegroundColor Yellow
    Write-Host "    L'agent utilisera la plus recente (ID=7)" -ForegroundColor Cyan
} elseif ($count -eq 1) {
    Write-Host "[OK] Une seule entree pour ce serveur" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Aucune entree trouvee!" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== STATUT ===" -ForegroundColor Cyan

# Verifier si erreur 400 dans les derniers logs
$recentLogs = Get-Content $logFile -Tail 20
$hasError400 = $recentLogs | Where-Object { $_ -match "ERREUR.*400" }

if ($hasError400) {
    Write-Host "[!] Erreur 400 encore presente" -ForegroundColor Red
    Write-Host "    Attendez 3 minutes pour le prochain cycle" -ForegroundColor Yellow
} else {
    Write-Host "[OK] Pas d'erreur 400 recente!" -ForegroundColor Green
    Write-Host "    L'agent devrait fonctionner correctement" -ForegroundColor Green
}

Write-Host ""
Write-Host "Dashboard: https://white-river-053fc6703.2.azurestaticapps.net" -ForegroundColor Cyan