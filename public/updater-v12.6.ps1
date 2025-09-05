# ATLAS Updater v12.6 - ALIGNÉ AVEC AGENT v12.6
$script:Version = "12.6"
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
# FONCTION LOG AVEC TIMESTAMP
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        default { Write-Host $logEntry }
    }
    
    # Toujours écrire dans le log pour tracking
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -Force
}

# ════════════════════════════════════════════════════
# CHECK UPDATE v12.6
# ════════════════════════════════════════════════════
function Check-And-Update {
    Write-Log "="*50
    Write-Log "UPDATER v$($script:Version) START" "UPDATE"
    Write-Log "Host: $hostname" "INFO"
    
    try {
        # Token
        Write-Log "Obtention token SharePoint..." "INFO"
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        
        $token = $tokenResponse.access_token
        Write-Log "Token obtenu" "SUCCESS"
        
        # Headers
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        Write-Log "Recherche commandes dans SharePoint..." "INFO"
        
        # Récupérer les commandes
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET -ErrorAction Stop
        $allCommands = $response.d.results
        
        Write-Log "Total commandes trouvées: $($allCommands.Count)" "INFO"
        
        # Chercher commandes PENDING
        $pendingCommands = @()
        foreach ($cmd in $allCommands) {
            if ($cmd.Status -eq "PENDING") {
                $targetHost = if ($cmd.TargetHostname) { $cmd.TargetHostname } else { "ALL" }
                
                if ($targetHost -eq "ALL" -or $targetHost -eq $hostname) {
                    if ($cmd.CommandType -eq "UPDATE_ALL" -or $cmd.CommandType -eq "UPDATE") {
                        $pendingCommands += $cmd
                        Write-Log "Commande PENDING trouvée: ID=$($cmd.Id) v$($cmd.TargetVersion)" "INFO"
                    }
                }
            }
        }
        
        if ($pendingCommands.Count -eq 0) {
            Write-Log "Aucune commande PENDING" "INFO"
            return
        }
        
        Write-Log "$($pendingCommands.Count) commandes PENDING pour ce serveur" "INFO"
        
        # Prendre la plus récente (tri par Id décroissant)
        $updateCommand = $pendingCommands | Sort-Object -Property Id -Descending | Select-Object -First 1
        $commandId = $updateCommand.Id
        $newVersion = $updateCommand.TargetVersion
        
        Write-Log ">>> COMMANDE SELECTIONNEE: ID=$commandId v$newVersion <<<" "SUCCESS"
        
        # Vérifier si déjà installée
        $currentAgentPath = "C:\SYAGA-ATLAS\agent.ps1"
        if (Test-Path $currentAgentPath) {
            $currentContent = Get-Content $currentAgentPath -Raw
            if ($currentContent -match 'Version\s*=\s*"([^"]+)"') {
                $currentVersion = $matches[1]
                Write-Log "Version actuelle: v$currentVersion" "INFO"
                
                if ($currentVersion -eq $newVersion) {
                    Write-Log "Version $newVersion déjà installée - Marquage DONE" "WARNING"
                    
                    # Marquer comme DONE quand même
                    $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($commandId)"
                    $updateBody = @{
                        "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
                        Status = "DONE"
                        ExecutedBy = "$hostname (already installed)"
                    } | ConvertTo-Json
                    
                    $updateHeaders = $headers + @{
                        "Content-Type" = "application/json;odata=verbose;charset=utf-8"
                        "X-HTTP-Method" = "MERGE"
                        "IF-MATCH" = "*"
                    }
                    
                    Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $updateBody -ErrorAction Stop
                    Write-Log "Commande $commandId marquée DONE" "SUCCESS"
                    return
                }
            }
        }
        
        # Télécharger nouvelle version
        Write-Log "Téléchargement agent v$newVersion..." "UPDATE"
        
        $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$newVersion.ps1"
        $tempPath = "C:\SYAGA-ATLAS\agent_v$newVersion.ps1"
        
        Invoke-WebRequest -Uri $newAgentUrl -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
        
        if (!(Test-Path $tempPath)) {
            Write-Log "Erreur: Fichier non téléchargé" "ERROR"
            return
        }
        
        Write-Log "Agent v$newVersion téléchargé ($(Get-Item $tempPath).Length bytes)" "SUCCESS"
        
        # Arrêter l'agent actuel
        Write-Log "Arrêt de l'agent actuel..." "INFO"
        Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        
        # Backup et remplacement
        $backupPath = "C:\SYAGA-ATLAS\agent_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
        if (Test-Path $currentAgentPath) {
            Copy-Item $currentAgentPath $backupPath -Force
            Write-Log "Backup créé: $backupPath" "INFO"
        }
        
        Copy-Item $tempPath $currentAgentPath -Force
        Write-Log "Agent remplacé par v$newVersion" "SUCCESS"
        
        # Nettoyer le fichier temporaire
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        
        # Marquer la commande comme DONE
        Write-Log "Marquage commande ID=$commandId comme DONE..." "INFO"
        
        $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($commandId)"
        $updateBody = @{
            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
            Status = "DONE"
            ExecutedBy = $hostname
        } | ConvertTo-Json
        
        $updateHeaders = $headers + @{
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
            "X-HTTP-Method" = "MERGE"
            "IF-MATCH" = "*"
        }
        
        Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $updateBody -ErrorAction Stop
        Write-Log "Commande $commandId marquée DONE par $hostname" "SUCCESS"
        
        # Relancer l'agent
        Write-Log "Démarrage du nouvel agent v$newVersion..." "INFO"
        Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        
        Write-Log ">>> MISE A JOUR REUSSIE: v$newVersion <<<" "SUCCESS"
        
    } catch {
        Write-Log "ERREUR: $_" "ERROR"
        Write-Log "StackTrace: $($_.ScriptStackTrace)" "ERROR"
    } finally {
        Write-Log "UPDATER v$($script:Version) END" "UPDATE"
        Write-Log "="*50
    }
}

# ════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════
Check-And-Update
exit 0