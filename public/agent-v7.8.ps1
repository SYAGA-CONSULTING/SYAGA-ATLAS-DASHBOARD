# ATLAS Agent v7.8 - SANS EMOJIS (fix erreur 400)
$script:Version = "7.8"
$hostname = $env:COMPUTERNAME
$configPath = "C:\SYAGA-ATLAS\config.json"
$logFile = "C:\SYAGA-ATLAS\atlas_log.txt"

# ════════════════════════════════════════════════════
# SHAREPOINT CONFIG
# ════════════════════════════════════════════════════
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
$commandsListId = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

# Buffer de logs pour cette exécution
$script:LogsBuffer = ""

# ════════════════════════════════════════════════════
# FONCTION LOG (SANS EMOJIS)
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ajouter au buffer pour SharePoint (nettoyer les caractères spéciaux)
    $cleanEntry = $logEntry -replace '[^\x00-\x7F]', ''
    $script:LogsBuffer += "$cleanEntry`r`n"
    
    # Afficher
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Cyan }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        default { Write-Host $logEntry }
    }
    
    # Sauvegarder localement
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
}

# ════════════════════════════════════════════════════
# FONCTION CHECK AUTO-UPDATE
# ════════════════════════════════════════════════════
function Check-AutoUpdate {
    Write-Log "===== CHECK AUTO-UPDATE v$($script:Version) DEMARRE =====" "UPDATE"
    
    try {
        # Token
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        Write-Log "Obtention token SharePoint..." "DEBUG"
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $token = $tokenResponse.access_token
        Write-Log "Token obtenu OK" "SUCCESS"
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        # Recherche commande UPDATE_ALL
        Write-Log "Recherche commandes UPDATE dans ATLAS-Commands..." "DEBUG"
        Write-Log "Liste ID: $commandsListId" "DEBUG"
        
        $searchUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items?`$filter=Status eq 'PENDING' and (TargetHostname eq 'ALL' or TargetHostname eq '$hostname')&`$select=Id,Title,CommandType,Status,TargetVersion,TargetHostname&`$orderby=Created desc"
        
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        $commands = $response.d.results
        
        Write-Log "Trouve $($commands.Count) commande(s) PENDING" "UPDATE"
        
        foreach ($cmd in $commands) {
            Write-Log "Commande: $($cmd.CommandType) pour $($cmd.TargetHostname)" "UPDATE"
            
            if ($cmd.CommandType -eq "UPDATE_ALL" -or $cmd.CommandType -eq "UPDATE") {
                Write-Log ">>> COMMANDE UPDATE DETECTEE <<<" "SUCCESS"
                Write-Log "Version cible: v$($cmd.TargetVersion)" "UPDATE"
                
                # Récupérer nouvelle version
                $newVersion = if ($cmd.TargetVersion) { $cmd.TargetVersion } else { "7.8" }
                
                Write-Log "Telechargement agent v$newVersion..." "UPDATE"
                
                # Télécharger
                $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$newVersion.ps1"
                $newAgentPath = "C:\SYAGA-ATLAS\agent_new.ps1"
                
                try {
                    Invoke-WebRequest -Uri $newAgentUrl -OutFile $newAgentPath -UseBasicParsing
                    
                    if (Test-Path $newAgentPath) {
                        Write-Log "Agent v$newVersion telecharge OK" "SUCCESS"
                        
                        # Backup
                        Copy-Item "C:\SYAGA-ATLAS\agent.ps1" "C:\SYAGA-ATLAS\agent_backup.ps1" -Force
                        
                        # Remplacer
                        Move-Item $newAgentPath "C:\SYAGA-ATLAS\agent.ps1" -Force
                        
                        Write-Log "MISE A JOUR REUSSIE vers v$newVersion" "SUCCESS"
                        
                        # Marquer DONE
                        $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($($cmd.Id))"
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
                        
                        Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $updateBody
                        Write-Log "Commande marquee DONE" "SUCCESS"
                        
                        Write-Log "Redemarrage dans 5 secondes..." "WARNING"
                        Start-Sleep -Seconds 5
                        exit 0
                    }
                } catch {
                    Write-Log "Erreur telechargement: $_" "ERROR"
                }
            }
        }
        
        if ($commands.Count -eq 0) {
            Write-Log "Aucune commande UPDATE trouvee" "DEBUG"
        }
        
    } catch {
        Write-Log "Erreur check update: $_" "ERROR"
    }
    
    Write-Log "===== CHECK AUTO-UPDATE TERMINE =====" "UPDATE"
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT + LOGS
# ════════════════════════════════════════════════════
function Send-HeartbeatWithLogs {
    try {
        Write-Log "Envoi heartbeat + logs..." "DEBUG"
        
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
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
        }
        
        # Métriques
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        
        $ramUsedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        $ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $diskTotalGB = [math]::Round($disk.Size / 1GB, 2)
        
        Write-Log "RAM: $ramUsedGB/$ramTotalGB GB - Disk: $diskFreeGB GB free" "DEBUG"
        
        # Vérifier existence
        $searchUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items?`$filter=Hostname eq '$hostname'"
        $existing = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        
        # Nettoyer les logs de tous les caractères spéciaux
        $cleanLogs = $script:LogsBuffer -replace '[^\x00-\x7F]', ''
        
        # Données
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            State = "ONLINE"
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = $script:Version
            RAMUsedGB = $ramUsedGB
            RAMTotalGB = $ramTotalGB
            DiskFreeGB = $diskFreeGB
            DiskTotalGB = $diskTotalGB
            Logs = $cleanLogs
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        if ($existing.d.results.Count -gt 0) {
            # Update existant
            $itemId = $existing.d.results[0].Id
            $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items($itemId)"
            
            $updateHeaders = $headers + @{
                "X-HTTP-Method" = "MERGE"
                "IF-MATCH" = "*"
            }
            
            Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $jsonData
            Write-Log "Heartbeat + Logs mis a jour OK" "SUCCESS"
        } else {
            # Créer nouveau
            $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
            Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
            Write-Log "Heartbeat + Logs cree OK" "SUCCESS"
        }
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  ATLAS AGENT v$($script:Version) - SANS EMOJIS" -ForegroundColor Cyan
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Installation si demandé
if ($args -contains "-Install") {
    Write-Log "Installation de l'agent v$($script:Version)..." "UPDATE"
    
    # Créer répertoire
    New-Item -ItemType Directory -Path "C:\SYAGA-ATLAS" -Force | Out-Null
    
    # Copier script
    Copy-Item $MyInvocation.MyCommand.Path "C:\SYAGA-ATLAS\agent.ps1" -Force
    
    # Créer tâche planifiée
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue
    
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\SYAGA-ATLAS\agent.ps1`""
    
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) `
        -RepetitionInterval (New-TimeSpan -Minutes 1)
    
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask "SYAGA-ATLAS-Agent" -Action $action -Trigger $trigger -Principal $principal | Out-Null
    
    Write-Log "Installation terminee OK" "SUCCESS"
    Write-Log "Tache planifiee creee OK" "SUCCESS"
    
    # Envoyer tout
    Send-HeartbeatWithLogs
    exit 0
}

# Exécution normale
Write-Log "Demarrage agent v$($script:Version)" "INFO"
Write-Log "Hostname: $hostname" "INFO"

# Check auto-update
Check-AutoUpdate

# Envoyer heartbeat + logs ensemble
Send-HeartbeatWithLogs

Write-Log "Execution terminee" "SUCCESS"