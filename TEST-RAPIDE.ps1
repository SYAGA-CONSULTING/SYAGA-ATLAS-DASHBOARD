# TEST RAPIDE ATLAS - Sans caracteres speciaux

Write-Host ""
Write-Host "=== TEST RAPIDE ATLAS ===" -ForegroundColor Cyan
Write-Host ""

# 1. VERSION AGENT
Write-Host "[1] VERSION" -ForegroundColor Yellow
$agentFile = "C:\ATLAS\Agent\ATLAS-Agent-Current.ps1"
if (Test-Path $agentFile) {
    $content = Get-Content $agentFile -Raw
    if ($content -match '\$Script:Version\s*=\s*"([^"]+)"') {
        Write-Host "  Agent: $($matches[1])" -ForegroundColor Green
    }
}

# 2. TACHE
Write-Host ""
Write-Host "[2] TACHE" -ForegroundColor Yellow
$task = Get-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "  Etat: $($task.State)" -ForegroundColor $(if($task.State -eq "Ready"){"Green"}else{"Red"})
    $info = Get-ScheduledTaskInfo -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
    if ($info) {
        Write-Host "  Derniere exec: $($info.LastRunTime)" -ForegroundColor Gray
    }
}

# 3. DERNIERS LOGS
Write-Host ""
Write-Host "[3] LOGS RECENTS" -ForegroundColor Yellow
$logFile = "C:\ATLAS\Logs\Agent-$(Get-Date -Format 'yyyyMMdd').log"
if (Test-Path $logFile) {
    Get-Content $logFile -Tail 5 | ForEach-Object {
        if ($_ -match "ERREUR") {
            Write-Host "  $_" -ForegroundColor Red
        } elseif ($_ -match "SUCCES") {
            Write-Host "  $_" -ForegroundColor Green
        } else {
            Write-Host "  $_" -ForegroundColor Gray
        }
    }
}

# 4. TEST SHAREPOINT
Write-Host ""
Write-Host "[4] TEST SHAREPOINT" -ForegroundColor Yellow
$configFile = "C:\ATLAS\config.json"
if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        
        # Test token
        $body = @{
            client_id = $config.ClientId
            scope = "https://graph.microsoft.com/.default"
            client_secret = $config.ClientSecret
            grant_type = "client_credentials"
        }
        
        $tokenUrl = "https://login.microsoftonline.com/$($config.TenantId)/oauth2/v2.0/token"
        
        try {
            $response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType "application/x-www-form-urlencoded"
            if ($response.access_token) {
                Write-Host "  Auth OK" -ForegroundColor Green
                
                # Test liste
                $headers = @{
                    "Authorization" = "Bearer $($response.access_token)"
                    "Accept" = "application/json"
                }
                
                $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$expand=fields&`$top=100"
                
                $items = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get
                
                $found = $false
                $updateFound = $false
                
                foreach ($item in $items.value) {
                    if ($item.fields.Title -eq $env:COMPUTERNAME) {
                        $found = $true
                        Write-Host "  SERVEUR TROUVE: $env:COMPUTERNAME" -ForegroundColor Green
                        Write-Host "    Version: $($item.fields.AgentVersion)" -ForegroundColor Gray
                        Write-Host "    Contact: $($item.fields.LastContact)" -ForegroundColor Gray
                    }
                    if ($item.fields.Title -eq "UPDATE_CONFIG") {
                        $updateFound = $true
                        Write-Host "  UPDATE_CONFIG: $($item.fields.AgentVersion)" -ForegroundColor Cyan
                    }
                }
                
                if (!$found) {
                    Write-Host "  SERVEUR NON TROUVE!" -ForegroundColor Red
                }
                
                Write-Host "  Total: $($items.value.Count) entrees" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  ERREUR: $_" -ForegroundColor Red
        }
    } catch {
        Write-Host "  Erreur config" -ForegroundColor Red
    }
} else {
    Write-Host "  Pas de config" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FIN TEST ===" -ForegroundColor Cyan