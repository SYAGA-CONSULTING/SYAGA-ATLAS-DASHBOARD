# ATLAS Updater v12.1 - FIX RÉCUPÉRATION ID
$script:Version = "12.1"
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
        default { Write-Host $logEntry }
    }
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# CHECK UPDATE (MÉTHODE v11.1 + FIX ID)
# ════════════════════════════════════════════════════
function Check-And-Update {
    Write-Log "UPDATER v$($script:Version) - Check update" "UPDATE"
    
    try {
        # Token
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $token = $tokenResponse.access_token
        Write-Log "Token OK" "SUCCESS"
        
        # WebClient (méthode v9.1)
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("Authorization", "Bearer $token")
        $webClient.Headers.Add("Accept", "application/json;odata=verbose")
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        Write-Log "Recherche commandes..."
        
        $jsonResponse = $webClient.DownloadString($searchUrl)
        
        # Nettoyer clés dupliquées
        $cleanedJson = $jsonResponse -replace ',"ID":\d+', ''
        
        $response = $cleanedJson | ConvertFrom-Json
        $allCommands = $response.d.results
        
        Write-Log "Total: $($allCommands.Count) commandes"
        
        # v11.0: Chercher TOUTES les commandes PENDING et prendre la PLUS RECENTE
        $pendingCommands = @()
        foreach ($cmd in $allCommands) {
            if ($cmd.Status -eq "PENDING") {
                $targetHost = if ($cmd.TargetHostname) { $cmd.TargetHostname } else { "ALL" }
                
                if ($targetHost -eq "ALL" -or $targetHost -eq $hostname) {
                    if ($cmd.CommandType -eq "UPDATE_ALL" -or $cmd.CommandType -eq "UPDATE") {
                        $pendingCommands += $cmd
                    }
                }
            }
        }
        
        # Prendre la plus RECENTE (par Created ou Id)
        $updateCommand = $null
        if ($pendingCommands.Count -gt 0) {
            Write-Log "$($pendingCommands.Count) commandes PENDING trouvees"
            
            # v12.1: Trier par Id ou ID (gestion casse)
            foreach ($cmd in $pendingCommands) {
                if (-not $cmd.Id -and $cmd.ID) {
                    $cmd | Add-Member -MemberType NoteProperty -Name "Id" -Value $cmd.ID -Force
                }
            }
            
            $updateCommand = $pendingCommands | Sort-Object -Property Id -Descending | Select-Object -First 1
            
            # v12.1: Récupérer l'ID correctement
            $commandId = if ($updateCommand.Id) { $updateCommand.Id } elseif ($updateCommand.ID) { $updateCommand.ID } else { "Unknown" }
            Write-Log ">>> COMMANDE LA PLUS RECENTE: ID $commandId v$($updateCommand.TargetVersion) <<<" "SUCCESS"
            
            # NETTOYER les anciennes
            foreach ($oldCmd in $pendingCommands) {
                $oldId = if ($oldCmd.Id) { $oldCmd.Id } elseif ($oldCmd.ID) { $oldCmd.ID } else { $null }
                if ($oldId -and $oldId -ne $commandId) {
                    Write-Log "Nettoyage ancienne commande ID $oldId v$($oldCmd.TargetVersion)" "WARNING"
                    try {
                        $cleanUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($oldId)"
                        $cleanBody = @{
                            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
                            Status = "OBSOLETE"
                        } | ConvertTo-Json
                        $cleanHeaders = @{
                            "Authorization" = "Bearer $token"
                            "Accept" = "application/json;odata=verbose"
                            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
                            "X-HTTP-Method" = "MERGE"
                            "IF-MATCH" = "*"
                        }
                        Invoke-RestMethod -Uri $cleanUrl -Headers $cleanHeaders -Method POST -Body $cleanBody
                    } catch {
                        # Pas grave si echec
                    }
                }
            }
        }
        
        if ($updateCommand) {
            $newVersion = $updateCommand.TargetVersion
            Write-Log "Telechargement agent v$newVersion..." "UPDATE"
            
            $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$newVersion.ps1"
            $tempPath = "C:\SYAGA-ATLAS\agent_temp.ps1"
            
            # Télécharger
            Invoke-WebRequest -Uri $newAgentUrl -OutFile $tempPath -UseBasicParsing
            
            if (Test-Path $tempPath) {
                Write-Log "Agent telecharge OK" "SUCCESS"
                
                # Arrêter la tâche agent si en cours
                Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                
                # Remplacer
                $agentPath = "C:\SYAGA-ATLAS\agent.ps1"
                $backupPath = "C:\SYAGA-ATLAS\agent_backup.ps1"
                
                if (Test-Path $agentPath) {
                    Copy-Item $agentPath $backupPath -Force
                }
                
                Move-Item $tempPath $agentPath -Force
                
                Write-Log ">>> MISE A JOUR REUSSIE vers v$newVersion <<<" "SUCCESS"
                
                # Marquer DONE (v12.1 avec ID correct)
                $cmdId = if ($updateCommand.Id) { $updateCommand.Id } elseif ($updateCommand.ID) { $updateCommand.ID } else { $null }
                Write-Log "Marquage commande ID $cmdId comme DONE"
                
                if ($cmdId) {
                    $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($cmdId)"
                    $updateBody = @{
                        "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
                        Status = "DONE"
                        ExecutedBy = $hostname
                    } | ConvertTo-Json
                    
                    $updateHeaders = @{
                        "Authorization" = "Bearer $token"
                        "Accept" = "application/json;odata=verbose"
                        "Content-Type" = "application/json;odata=verbose;charset=utf-8"
                        "X-HTTP-Method" = "MERGE"
                        "IF-MATCH" = "*"
                    }
                    
                    try {
                        Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $updateBody
                        Write-Log "Commande $cmdId marquee DONE" "SUCCESS"
                    } catch {
                        Write-Log "Erreur marquage ID $cmdId : $_" "WARNING"
                    }
                } else {
                    Write-Log "Pas d'ID trouve pour marquer DONE" "WARNING"
                }
                
                # Relancer la tâche agent
                Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
                Write-Log "Tache agent relancee"
            }
        } else {
            Write-Log "Aucune mise a jour disponible"
        }
        
        $webClient.Dispose()
        
    } catch {
        Write-Log "Erreur: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════
Write-Log "="*50
Write-Log "UPDATER v$($script:Version) demarre - FIX ID" "UPDATE"

Check-And-Update

Write-Log "Fin updater"
Write-Log "="*50
exit 0