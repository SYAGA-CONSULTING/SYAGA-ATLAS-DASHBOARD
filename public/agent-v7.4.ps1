# ATLAS Agent v7.4 - LOGS COMPLETS DANS SHAREPOINT DOCUMENTS
$script:Version = "7.4"
$hostname = $env:COMPUTERNAME
$configPath = "C:\SYAGA-ATLAS\config.json"
$logFile = "C:\SYAGA-ATLAS\atlas_log.txt"

# ════════════════════════════════════════════════════
# SHAREPOINT - LOGS DANS DOCUMENTS
# ════════════════════════════════════════════════════
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
$commandsListId = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

# Buffer de logs
$script:LogBuffer = @()

# ════════════════════════════════════════════════════
# FONCTION LOG AMÉLIORÉE
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ajouter au buffer
    $script:LogBuffer += @{
        Time = $timestamp
        Level = $Level
        Message = $Message
    }
    
    # Afficher et sauvegarder
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Cyan }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        default { Write-Host $logEntry }
    }
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
}

# ════════════════════════════════════════════════════
# FONCTION UPLOAD LOGS VERS SHAREPOINT DOCUMENTS
# ════════════════════════════════════════════════════
function Upload-LogsToSharePoint {
    param($Context)
    
    try {
        Write-Log "Envoi des logs vers SharePoint Documents..." "DEBUG"
        
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
        }
        
        # Créer le contenu du log complet
        $logContent = @"
═══════════════════════════════════════════════════════════════
ATLAS AGENT v$($script:Version) - LOG COMPLET
Serveur: $hostname
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Context: $Context
═══════════════════════════════════════════════════════════════

"@
        
        # Ajouter tous les logs du buffer
        foreach ($log in $script:LogBuffer) {
            $logContent += "[$($log.Time)] [$($log.Level)] $($log.Message)`r`n"
        }
        
        # Nom du fichier
        $fileName = "ATLAS_${hostname}_$(Get-Date -Format 'yyyyMMdd_HHmmss')_${Context}.txt"
        
        # Upload vers Documents/ATLAS-Logs
        $uploadUrl = "https://${siteName}.sharepoint.com/_api/web/GetFolderByServerRelativeUrl('/Shared%20Documents/ATLAS-Logs')/Files/add(url='$fileName',overwrite=true)"
        
        # Créer le dossier si nécessaire
        $folderCheckUrl = "https://${siteName}.sharepoint.com/_api/web/GetFolderByServerRelativeUrl('/Shared%20Documents/ATLAS-Logs')"
        try {
            $null = Invoke-RestMethod -Uri $folderCheckUrl -Headers $headers -Method GET
        } catch {
            # Créer le dossier
            $createFolderUrl = "https://${siteName}.sharepoint.com/_api/web/folders"
            $folderBody = @{
                "__metadata" = @{ type = "SP.Folder" }
                ServerRelativeUrl = "/Shared Documents/ATLAS-Logs"
            } | ConvertTo-Json
            
            $null = Invoke-RestMethod -Uri $createFolderUrl -Headers $headers -Method POST -Body $folderBody -ContentType "application/json;odata=verbose;charset=utf-8"
        }
        
        # Upload du fichier
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($logContent)
        $uploadHeaders = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Length" = $bytes.Length
        }
        
        $response = Invoke-RestMethod -Uri $uploadUrl -Headers $uploadHeaders -Method POST -Body $bytes
        
        Write-Log "✅ Logs uploadés: $fileName" "SUCCESS"
        
        # Vider le buffer après upload réussi
        $script:LogBuffer = @()
        
        return $true
        
    } catch {
        Write-Log "Erreur upload logs: $_" "ERROR"
        return $false
    }
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
        Write-Log "Token obtenu" "DEBUG"
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        # Recherche commande UPDATE_ALL
        Write-Log "Recherche commandes UPDATE dans ATLAS-Commands..." "DEBUG"
        $searchUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items?`$filter=Status eq 'PENDING' and (TargetHostname eq 'ALL' or TargetHostname eq '$hostname')&`$select=Title,CommandType,Status,Parameters,TargetHostname&`$orderby=Created desc"
        
        Write-Log "URL: $searchUrl" "DEBUG"
        
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        $commands = $response.d.results
        
        Write-Log "Trouvé $($commands.Count) commande(s) PENDING" "UPDATE"
        
        foreach ($cmd in $commands) {
            Write-Log "Commande: $($cmd.CommandType) pour $($cmd.TargetHostname)" "DEBUG"
            
            if ($cmd.CommandType -eq "UPDATE_ALL" -or $cmd.CommandType -eq "UPDATE") {
                Write-Log "🚀 COMMANDE UPDATE DÉTECTÉE !" "UPDATE"
                
                # Récupérer nouvelle version depuis Parameters
                $newVersion = "7.4"  # Par défaut
                if ($cmd.Parameters) {
                    if ($cmd.Parameters -match "v?([\d\.]+)") {
                        $newVersion = $matches[1]
                    }
                }
                
                Write-Log "Téléchargement agent v$newVersion..." "UPDATE"
                
                # Télécharger depuis public
                $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$newVersion.ps1"
                $newAgentPath = "C:\SYAGA-ATLAS\agent_new.ps1"
                
                try {
                    Invoke-WebRequest -Uri $newAgentUrl -OutFile $newAgentPath -UseBasicParsing
                    
                    if (Test-Path $newAgentPath) {
                        Write-Log "✅ Agent v$newVersion téléchargé" "SUCCESS"
                        
                        # Backup ancien
                        Copy-Item "C:\SYAGA-ATLAS\agent.ps1" "C:\SYAGA-ATLAS\agent_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1" -Force
                        
                        # Remplacer
                        Move-Item $newAgentPath "C:\SYAGA-ATLAS\agent.ps1" -Force
                        
                        Write-Log "🎉 MISE À JOUR RÉUSSIE vers v$newVersion" "SUCCESS"
                        
                        # Marquer commande comme DONE
                        $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($($cmd.Id))"
                        $updateBody = @{
                            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
                            Status = "DONE"
                        } | ConvertTo-Json
                        
                        $updateHeaders = @{
                            "Authorization" = "Bearer $token"
                            "Accept" = "application/json;odata=verbose"
                            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
                            "X-HTTP-Method" = "MERGE"
                            "IF-MATCH" = "*"
                        }
                        
                        Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $updateBody
                        
                        # Upload logs avant redémarrage
                        Upload-LogsToSharePoint -Context "UPDATE_SUCCESS_v$newVersion"
                        
                        Write-Log "Redémarrage dans 5 secondes..." "WARNING"
                        Start-Sleep -Seconds 5
                        exit 0
                    }
                } catch {
                    Write-Log "Erreur téléchargement: $_" "ERROR"
                }
            }
        }
        
        if ($commands.Count -eq 0) {
            Write-Log "Aucune commande UPDATE trouvée" "DEBUG"
        }
        
    } catch {
        Write-Log "Erreur check update: $_" "ERROR"
    }
    
    Write-Log "===== CHECK AUTO-UPDATE TERMINÉ =====" "UPDATE"
}

# ════════════════════════════════════════════════════
# FONCTION ENVOI HEARTBEAT
# ════════════════════════════════════════════════════
function Send-Heartbeat {
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
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
        }
        
        # Métriques
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $cpu = Get-WmiObject -Class Win32_Processor
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        
        $ramUsedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        $ramTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $diskTotalGB = [math]::Round($disk.Size / 1GB, 2)
        
        # Vérifier existence
        $searchUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items?`$filter=Hostname eq '$hostname'"
        $existing = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        
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
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        if ($existing.d.results.Count -gt 0) {
            # Update
            $itemId = $existing.d.results[0].Id
            $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items($itemId)"
            $updateHeaders = $headers + @{
                "X-HTTP-Method" = "MERGE"
                "IF-MATCH" = "*"
            }
            Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $jsonData
            Write-Log "Heartbeat mis à jour" "SUCCESS"
        } else {
            # Create
            $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
            Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
            Write-Log "Heartbeat créé" "SUCCESS"
        }
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ATLAS AGENT v$($script:Version) - LOGS COMPLETS SHAREPOINT DOCS" -ForegroundColor Cyan
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
    Write-Log "Tâche planifiée créée (exécution/minute)" "SUCCESS"
    
    # Premier heartbeat
    Send-Heartbeat
    Upload-LogsToSharePoint -Context "INSTALLATION"
    exit 0
}

# Exécution normale
Write-Log "Démarrage agent v$($script:Version)" "INFO"

# Check auto-update
Check-AutoUpdate

# Heartbeat
Send-Heartbeat

# Upload logs
Upload-LogsToSharePoint -Context "HEARTBEAT"

Write-Log "Exécution terminée" "SUCCESS"