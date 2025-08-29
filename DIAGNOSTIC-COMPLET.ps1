# ============================================================
#  DIAGNOSTIC COMPLET ATLAS - Vérifie tout le système
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   DIAGNOSTIC COMPLET SYSTÈME ATLAS" -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 1. VÉRIFICATION INSTALLATION
Write-Host "[1] VÉRIFICATION INSTALLATION" -ForegroundColor Yellow
Write-Host "-----------------------------" -ForegroundColor Gray

$atlasPath = "C:\ATLAS"
$configFile = "$atlasPath\config.json"
$agentFile = "$atlasPath\Agent\ATLAS-Agent-Current.ps1"
$logFile = "$atlasPath\Logs\Agent-$(Get-Date -Format 'yyyyMMdd').log"

# Vérifier les fichiers
if (Test-Path $atlasPath) {
    Write-Host "  ✓ Dossier ATLAS existe: $atlasPath" -ForegroundColor Green
} else {
    Write-Host "  ✗ Dossier ATLAS manquant!" -ForegroundColor Red
}

if (Test-Path $configFile) {
    Write-Host "  ✓ Config existe: $configFile" -ForegroundColor Green
    
    # Lire la config
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($config.ClientSecret -and $config.ClientSecret -ne "AJOUTER_LE_SECRET_ICI") {
            Write-Host "  ✓ ClientSecret configuré" -ForegroundColor Green
        } else {
            Write-Host "  ✗ ClientSecret NON configuré!" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ✗ Erreur lecture config: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  ✗ Config manquante!" -ForegroundColor Red
}

if (Test-Path $agentFile) {
    Write-Host "  ✓ Agent existe: $agentFile" -ForegroundColor Green
    
    # Vérifier la version
    $content = Get-Content $agentFile -Raw
    if ($content -match '\$Script:Version\s*=\s*"([^"]+)"') {
        $version = $matches[1]
        Write-Host "  → Version agent: $version" -ForegroundColor Cyan
    }
} else {
    Write-Host "  ✗ Agent manquant!" -ForegroundColor Red
}

# 2. VÉRIFICATION TÂCHE PLANIFIÉE
Write-Host ""
Write-Host "[2] TÂCHE PLANIFIÉE" -ForegroundColor Yellow
Write-Host "-------------------" -ForegroundColor Gray

$task = Get-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "  ✓ Tâche existe: ATLAS-Agent-v5" -ForegroundColor Green
    Write-Host "  → État: $($task.State)" -ForegroundColor $(if($task.State -eq "Ready"){"Green"}else{"Red"})
    
    $taskInfo = Get-ScheduledTaskInfo -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
    if ($taskInfo) {
        Write-Host "  → Dernière exécution: $($taskInfo.LastRunTime)" -ForegroundColor Cyan
        Write-Host "  → Prochaine exécution: $($taskInfo.NextRunTime)" -ForegroundColor Cyan
        Write-Host "  → Code retour: $($taskInfo.LastTaskResult)" -ForegroundColor $(if($taskInfo.LastTaskResult -eq 0){"Green"}else{"Red"})
    }
} else {
    Write-Host "  ✗ Tâche manquante!" -ForegroundColor Red
}

# 3. DERNIERS LOGS
Write-Host ""
Write-Host "[3] DERNIERS LOGS (10 dernières lignes)" -ForegroundColor Yellow
Write-Host "---------------------------------------" -ForegroundColor Gray

if (Test-Path $logFile) {
    $logs = Get-Content $logFile -Tail 10
    foreach ($log in $logs) {
        if ($log -match "ERREUR") {
            Write-Host "  $log" -ForegroundColor Red
        } elseif ($log -match "SUCCES") {
            Write-Host "  $log" -ForegroundColor Green
        } elseif ($log -match "UPDATE") {
            Write-Host "  $log" -ForegroundColor Cyan
        } elseif ($log -match "AVERTISSEMENT") {
            Write-Host "  $log" -ForegroundColor Yellow
        } else {
            Write-Host "  $log" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "  ✗ Pas de logs trouvés" -ForegroundColor Red
}

# 4. TEST CONNEXION SHAREPOINT
Write-Host ""
Write-Host "[4] TEST CONNEXION SHAREPOINT" -ForegroundColor Yellow
Write-Host "-----------------------------" -ForegroundColor Gray

if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        
        if ($config.ClientSecret -and $config.ClientSecret -ne "AJOUTER_LE_SECRET_ICI") {
            Write-Host "  → Test authentification Azure AD..." -ForegroundColor Cyan
            
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
                    Write-Host "  ✓ Authentification réussie!" -ForegroundColor Green
                    
                    # Test lecture SharePoint
                    Write-Host "  → Test lecture liste SharePoint..." -ForegroundColor Cyan
                    $headers = @{
                        "Authorization" = "Bearer $($response.access_token)"
                        "Accept" = "application/json"
                    }
                    
                    $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$top=1"
                    
                    try {
                        $listResponse = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get
                        Write-Host "  ✓ Connexion SharePoint OK!" -ForegroundColor Green
                        
                        # Compter les entrées
                        $allItemsUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$expand=fields"
                        $allItems = Invoke-RestMethod -Uri $allItemsUrl -Headers $headers -Method Get
                        
                        $serverCount = 0
                        $updateConfig = $false
                        $thisServer = $null
                        
                        foreach ($item in $allItems.value) {
                            if ($item.fields.Title -eq "UPDATE_CONFIG" -or $item.fields.Hostname -eq "UPDATE_CONFIG") {
                                $updateConfig = $true
                                Write-Host "  → UPDATE_CONFIG trouvé: Version $($item.fields.AgentVersion)" -ForegroundColor Cyan
                            } elseif ($item.fields.Title -eq $env:COMPUTERNAME) {
                                $thisServer = $item.fields
                                $serverCount++
                            } elseif ($item.fields.Hostname -and $item.fields.Hostname -ne "CONFIG") {
                                $serverCount++
                            }
                        }
                        
                        Write-Host "  → $serverCount serveur(s) dans SharePoint" -ForegroundColor Cyan
                        
                        if ($thisServer) {
                            Write-Host "  ✓ CE SERVEUR ($env:COMPUTERNAME) est dans SharePoint!" -ForegroundColor Green
                            Write-Host "    - LastContact: $($thisServer.LastContact)" -ForegroundColor Gray
                            Write-Host "    - AgentVersion: $($thisServer.AgentVersion)" -ForegroundColor Gray
                            Write-Host "    - State: $($thisServer.State)" -ForegroundColor Gray
                        } else {
                            Write-Host "  ✗ CE SERVEUR ($env:COMPUTERNAME) N'EST PAS dans SharePoint!" -ForegroundColor Red
                        }
                        
                        if (!$updateConfig) {
                            Write-Host "  ⚠ Pas d'UPDATE_CONFIG (normal si pas de déploiement en cours)" -ForegroundColor Yellow
                        }
                        
                    } catch {
                        Write-Host "  ✗ Erreur lecture SharePoint: $_" -ForegroundColor Red
                    }
                    
                } else {
                    Write-Host "  ✗ Pas de token reçu" -ForegroundColor Red
                }
            } catch {
                Write-Host "  ✗ Erreur authentification: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "  ✗ ClientSecret non configuré - impossible de tester" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ✗ Erreur lecture config: $_" -ForegroundColor Red
    }
}

# 5. EXÉCUTION MANUELLE TEST
Write-Host ""
Write-Host "[5] TEST EXÉCUTION MANUELLE" -ForegroundColor Yellow
Write-Host "---------------------------" -ForegroundColor Gray

$response = Read-Host "  Voulez-vous exécuter l'agent maintenant pour test? (O/N)"
if ($response -eq "O") {
    Write-Host "  → Exécution de l'agent..." -ForegroundColor Cyan
    
    if (Test-Path $agentFile) {
        & $agentFile -Action Executer
    } else {
        Write-Host "  ✗ Agent introuvable!" -ForegroundColor Red
    }
}

# RÉSUMÉ
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   RÉSUMÉ DU DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$problems = @()

if (!(Test-Path $configFile)) { $problems += "Config manquante" }
if (!(Test-Path $agentFile)) { $problems += "Agent manquant" }
if (!$task) { $problems += "Tâche planifiée manquante" }
if ($task -and $task.State -ne "Ready") { $problems += "Tâche non active" }

if ($problems.Count -eq 0) {
    Write-Host ""
    Write-Host "  ✓✓✓ TOUT SEMBLE OK ✓✓✓" -ForegroundColor Green
    Write-Host ""
    Write-Host "  L'agent devrait envoyer des données toutes les 3 minutes." -ForegroundColor Cyan
    Write-Host "  Vérifiez le dashboard: https://white-river-053fc6703.2.azurestaticapps.net" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "  ✗✗✗ PROBLÈMES DÉTECTÉS ✗✗✗" -ForegroundColor Red
    Write-Host ""
    foreach ($problem in $problems) {
        Write-Host "  - $problem" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  Corrigez ces problèmes et relancez le diagnostic." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan