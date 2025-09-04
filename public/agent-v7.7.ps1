# ATLAS Agent v7.7 - DEBUG COMPLET POUR DIAGNOSTIQUER ERREUR 400
$script:Version = "7.7"
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
# FONCTION LOG
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ajouter au buffer pour SharePoint
    $script:LogsBuffer += "$logEntry`r`n"
    
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
    Write-Log "===== CHECK AUTO-UPDATE v$($script:Version) DÉMARRÉ =====" "UPDATE"
    
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
        Write-Log "✅ Token obtenu (longueur: $($token.Length))" "SUCCESS"
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        # Recherche commande UPDATE_ALL
        Write-Log "Recherche commandes dans ATLAS-Commands..." "DEBUG"
        Write-Log "Liste ID: $commandsListId" "DEBUG"
        
        $searchUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items?`$filter=Status eq 'PENDING' and (TargetHostname eq 'ALL' or TargetHostname eq '$hostname')&`$select=Id,Title,CommandType,Status,TargetVersion,TargetHostname&`$orderby=Created desc"
        
        Write-Log "URL complète: $searchUrl" "DEBUG"
        
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        $commands = $response.d.results
        
        Write-Log "🔍 Trouvé $($commands.Count) commande(s) PENDING" "UPDATE"
        
        foreach ($cmd in $commands) {
            Write-Log "📌 Commande: $($cmd.CommandType) pour $($cmd.TargetHostname)" "UPDATE"
            
            if ($cmd.CommandType -eq "UPDATE_ALL" -or $cmd.CommandType -eq "UPDATE") {
                Write-Log "🚀 COMMANDE UPDATE DÉTECTÉE !" "SUCCESS"
                Write-Log "Version cible: v$($cmd.TargetVersion)" "UPDATE"
                
                # Récupérer nouvelle version
                $newVersion = if ($cmd.TargetVersion) { $cmd.TargetVersion } else { "7.7" }
                
                Write-Log "Téléchargement agent v$newVersion..." "UPDATE"
                
                # Télécharger
                $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$newVersion.ps1"
                $newAgentPath = "C:\SYAGA-ATLAS\agent_new.ps1"
                
                try {
                    Invoke-WebRequest -Uri $newAgentUrl -OutFile $newAgentPath -UseBasicParsing
                    
                    if (Test-Path $newAgentPath) {
                        Write-Log "✅ Agent v$newVersion téléchargé" "SUCCESS"
                        
                        # Backup
                        Copy-Item "C:\SYAGA-ATLAS\agent.ps1" "C:\SYAGA-ATLAS\agent_backup.ps1" -Force
                        
                        # Remplacer
                        Move-Item $newAgentPath "C:\SYAGA-ATLAS\agent.ps1" -Force
                        
                        Write-Log "🎉 MISE À JOUR RÉUSSIE vers v$newVersion" "SUCCESS"
                        
                        # Marquer DONE
                        $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($($cmd.Id))"
                        $updateBody = @{
                            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
                            Status = "DONE"
                            ExecutedBy = $hostname
                        } | ConvertTo-Json
                        
                        Write-Log "Marquage commande DONE..." "DEBUG"
                        Write-Log "URL: $updateUrl" "DEBUG"
                        
                        $updateHeaders = @{
                            "Authorization" = "Bearer $token"
                            "Accept" = "application/json;odata=verbose"
                            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
                            "X-HTTP-Method" = "MERGE"
                            "IF-MATCH" = "*"
                        }
                        
                        Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $updateBody
                        Write-Log "✅ Commande marquée DONE" "SUCCESS"
                        
                        Write-Log "Redémarrage dans 5 secondes..." "WARNING"
                        Start-Sleep -Seconds 5
                        exit 0
                    }
                } catch {
                    Write-Log "❌ Erreur téléchargement: $_" "ERROR"
                }
            }
        }
        
        if ($commands.Count -eq 0) {
            Write-Log "Aucune commande UPDATE trouvée" "DEBUG"
        }
        
    } catch {
        Write-Log "❌ Erreur check update: $_" "ERROR"
        Write-Log "Stack trace: $($_.Exception.StackTrace)" "ERROR"
    }
    
    Write-Log "===== CHECK AUTO-UPDATE TERMINÉ =====" "UPDATE"
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT + LOGS (TOUT EN UN)
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
        
        Write-Log "Obtention token pour heartbeat..." "DEBUG"
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $token = $tokenResponse.access_token
        Write-Log "Token obtenu pour heartbeat" "DEBUG"
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
        }
        
        # Métriques
        Write-Log "Collecte des métriques..." "DEBUG"
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        
        $ramUsedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        $ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $diskTotalGB = [math]::Round($disk.Size / 1GB, 2)
        
        Write-Log "RAM: $ramUsedGB/$ramTotalGB GB" "DEBUG"
        Write-Log "Disk: $diskFreeGB/$diskTotalGB GB free" "DEBUG"
        
        # Vérifier existence
        Write-Log "Vérification existence serveur..." "DEBUG"
        $searchUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items?`$filter=Hostname eq '$hostname'"
        Write-Log "URL recherche: $searchUrl" "DEBUG"
        
        $existing = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        Write-Log "Résultat recherche: $($existing.d.results.Count) item(s)" "DEBUG"
        
        # Préparer les données
        Write-Log "Préparation des données..." "DEBUG"
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
            Logs = $script:LogsBuffer  # LOGS ICI
        }
        
        Write-Log "Champs préparés:" "DEBUG"
        foreach ($key in $data.Keys) {
            if ($key -ne "Logs" -and $key -ne "__metadata") {
                Write-Log "  $key = $($data[$key])" "DEBUG"
            }
        }
        Write-Log "  Logs = $($script:LogsBuffer.Length) caractères" "DEBUG"
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        Write-Log "JSON généré (taille: $($jsonData.Length) octets)" "DEBUG"
        
        # DEBUG: Afficher le JSON pour voir le problème
        if ($jsonData.Length -lt 2000) {
            Write-Log "JSON complet: $jsonData" "DEBUG"
        } else {
            Write-Log "JSON (premiers 500 car): $($jsonData.Substring(0, 500))..." "DEBUG"
        }
        
        if ($existing.d.results.Count -gt 0) {
            # Update existant
            $itemId = $existing.d.results[0].Id
            Write-Log "Update item existant ID: $itemId" "DEBUG"
            
            $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items($itemId)"
            Write-Log "URL update: $updateUrl" "DEBUG"
            
            $updateHeaders = $headers + @{
                "X-HTTP-Method" = "MERGE"
                "IF-MATCH" = "*"
            }
            
            Write-Log "Headers: $($updateHeaders.Keys -join ', ')" "DEBUG"
            Write-Log "Envoi UPDATE..." "DEBUG"
            
            try {
                $result = Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $jsonData
                Write-Log "✅ Heartbeat + Logs mis à jour" "SUCCESS"
            } catch {
                Write-Log "❌ ERREUR UPDATE: $_" "ERROR"
                Write-Log "Response: $($_.Exception.Response)" "ERROR"
                
                # Essayer de lire le contenu de l'erreur
                if ($_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $responseBody = $reader.ReadToEnd()
                    Write-Log "Body erreur: $responseBody" "ERROR"
                }
            }
        } else {
            # Créer nouveau
            Write-Log "Création nouvel item..." "DEBUG"
            $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
            Write-Log "URL create: $createUrl" "DEBUG"
            
            try {
                $result = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
                Write-Log "✅ Heartbeat + Logs créé" "SUCCESS"
            } catch {
                Write-Log "❌ ERREUR CREATE: $_" "ERROR"
                Write-Log "Response: $($_.Exception.Response)" "ERROR"
                
                # Essayer de lire le contenu de l'erreur
                if ($_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $responseBody = $reader.ReadToEnd()
                    Write-Log "Body erreur: $responseBody" "ERROR"
                }
            }
        }
        
    } catch {
        Write-Log "❌ Erreur heartbeat général: $_" "ERROR"
        Write-Log "Stack trace: $($_.Exception.StackTrace)" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ATLAS AGENT v$($script:Version) - DEBUG COMPLET" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
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
    
    Write-Log "✅ Installation terminée" "SUCCESS"
    Write-Log "✅ Tâche planifiée créée" "SUCCESS"
    
    # Envoyer tout
    Send-HeartbeatWithLogs
    exit 0
}

# Exécution normale
Write-Log "Démarrage agent v$($script:Version)" "INFO"
Write-Log "Hostname: $hostname" "INFO"
Write-Log "Config: $configPath" "INFO"

# Check auto-update
Check-AutoUpdate

# Envoyer heartbeat + logs ensemble
Send-HeartbeatWithLogs

Write-Log "✅ Exécution terminée" "SUCCESS"