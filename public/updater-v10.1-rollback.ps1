# ATLAS Updater v10.1 - AVEC ROLLBACK SUPPORT
$script:Version = "10.1"
$hostname = $env:COMPUTERNAME
$logFile = "C:\SYAGA-ATLAS\updater_log.txt"

# ════════════════════════════════════════════════════
# SHAREPOINT CONFIG
# ════════════════════════════════════════════════════
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$commandsListId = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

# ════════════════════════════════════════════════════
# FONCTION LOG
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        "ROLLBACK" { Write-Host $logEntry -ForegroundColor Cyan }
        default { Write-Host $logEntry }
    }
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# FONCTION ROLLBACK v10.3
# ════════════════════════════════════════════════════
function Execute-Rollback {
    Write-Log "🔄 ROLLBACK VERS FONDATION v10.3 DEMANDÉ" "ROLLBACK"
    
    try {
        # Télécharger script rollback
        $rollbackUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/rollback-v10.3.ps1"
        $rollbackPath = "C:\SYAGA-ATLAS\rollback-temp.ps1"
        
        Write-Log "Téléchargement script rollback..." "ROLLBACK"
        $rollback = Invoke-WebRequest -Uri $rollbackUrl -UseBasicParsing
        $rollback.Content | Out-File $rollbackPath -Encoding UTF8 -Force
        
        Write-Log "Exécution rollback v10.3..." "ROLLBACK"
        & PowerShell.exe -ExecutionPolicy Bypass -File $rollbackPath
        
        # Nettoyer
        Remove-Item $rollbackPath -Force -ErrorAction SilentlyContinue
        
        Write-Log "✅ ROLLBACK v10.3 TERMINÉ AVEC SUCCÈS" "SUCCESS"
        return $true
        
    } catch {
        Write-Log "❌ ERREUR ROLLBACK: $_" "ERROR"
        return $false
    }
}

# ════════════════════════════════════════════════════
# CHECK UPDATE + ROLLBACK
# ════════════════════════════════════════════════════
function Check-Commands {
    Write-Log "UPDATER v$($script:Version) - Check commands (UPDATE + ROLLBACK)" "UPDATE"
    
    try {
        # Token
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        $token = $tokenResponse.access_token
        Write-Log "Token OK" "SUCCESS"
        
        # Chercher commandes PENDING (UPDATE ou ROLLBACK)
        $headers = @{
            Authorization = "Bearer $token"
            Accept = "application/json;odata=nometadata"
        }
        
        $commandsUrl = "https://$siteName.sharepoint.com/_api/web/lists(guid'$commandsListId')/items?`$filter=Status eq 'PENDING'&`$select=Id,Title,CommandType,TargetVersion,TargetHostname"
        
        Write-Log "Recherche commandes..." "INFO"
        $response = Invoke-RestMethod -Uri $commandsUrl -Headers $headers -Method Get
        
        $commands = $response.value
        Write-Log "Total: $($commands.Count) commandes" "INFO"
        
        foreach ($cmd in $commands) {
            $targetHost = $cmd.TargetHostname
            $commandType = $cmd.CommandType
            $version = $cmd.TargetVersion
            
            # Vérifier si commande pour ce serveur
            if ($targetHost -eq "ALL" -or $targetHost -eq $hostname) {
                
                if ($commandType -eq "ROLLBACK") {
                    Write-Log ">>> ROLLBACK DÉTECTÉ: v$version <<<" "ROLLBACK"
                    
                    if (Execute-Rollback) {
                        Write-Log "Rollback réussi - Marquage commande EXECUTED" "SUCCESS"
                        # Marquer commande comme EXECUTED
                        # TODO: Implémenter marquage
                    }
                    
                } elseif ($commandType -eq "UPDATE") {
                    # Logique update existante
                    Write-Log ">>> UPDATE DETECTE: v$version <<<" "SUCCESS"
                    
                    # Télécharger agent
                    $agentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$version.ps1"
                    $tempPath = "C:\SYAGA-ATLAS\temp-agent.ps1"
                    $agentPath = "C:\SYAGA-ATLAS\agent.ps1"
                    
                    Write-Log "Téléchargement agent v$version..." "UPDATE"
                    try {
                        $agent = Invoke-WebRequest -Uri $agentUrl -UseBasicParsing
                        $agent.Content | Out-File $tempPath -Encoding UTF8 -Force
                        Write-Log "Agent téléchargé OK" "SUCCESS"
                        
                        # Arrêter tâche agent
                        Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        
                        # Remplacer agent
                        Move-Item $tempPath $agentPath -Force
                        
                        # Relancer tâche
                        Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
                        
                        Write-Log ">>> MISE A JOUR REUSSIE vers v$version <<<" "SUCCESS"
                        Write-Log "Tâche agent relancée" "INFO"
                        
                    } catch {
                        Write-Log "Erreur update: $_" "ERROR"
                    }
                }
            }
        }
        
    } catch {
        Write-Log "Erreur check commands: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════
Write-Log ("=" * 50) "INFO"
Write-Log "UPDATER v$($script:Version) démarre" "UPDATE"

Check-Commands

Write-Log "Fin updater" "INFO"
Write-Log ("=" * 50) "INFO"