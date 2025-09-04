# ATLAS Agent v8.6 - FIX ÉCHAPPEMENT $ DANS URL
$script:Version = "8.6"
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

# Buffer de logs
$script:LogsBuffer = ""

# ════════════════════════════════════════════════════
# FONCTION LOG
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ajouter au buffer (nettoyer caractères spéciaux)
    $cleanEntry = $logEntry -replace '[^\x20-\x7E]', ' '
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
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# FONCTION CHECK AUTO-UPDATE (FIX ÉCHAPPEMENT)
# ════════════════════════════════════════════════════
function Check-AutoUpdate {
    Write-Log "CHECK AUTO-UPDATE v$($script:Version)" "UPDATE"
    
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
        Write-Log "Token obtenu" "SUCCESS"
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        # IMPORTANT: Utiliser un string literal pour éviter l'échappement
        Write-Log "Recherche commandes dans SharePoint..." "DEBUG"
        
        # Construction de l'URL sans backticks
        $baseUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        $query = '?$select=Id,Title,CommandType,Status,TargetVersion,TargetHostname&$top=100'
        $searchUrl = $baseUrl + $query
        
        Write-Log "URL: $searchUrl" "DEBUG"
        
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        $allCommands = $response.d.results
        
        Write-Log "Total commandes recues: $($allCommands.Count)" "DEBUG"
        
        # Debug - Afficher les 5 premières
        $count = 0
        foreach ($cmd in $allCommands) {
            if ($count -lt 5) {
                Write-Log "  Cmd: $($cmd.Title) | Type=$($cmd.CommandType) | Status=$($cmd.Status) | Target=$($cmd.TargetHostname)" "DEBUG"
                $count++
            }
        }
        
        # Filtrer localement avec gestion NULL
        $pendingCommands = @()
        foreach ($cmd in $allCommands) {
            # Vérifier que Status existe et est PENDING
            if ($cmd.Status -and $cmd.Status -eq "PENDING") {
                Write-Log "PENDING trouvee: $($cmd.Title)" "DEBUG"
                
                # Vérifier que c'est pour ce serveur ou ALL
                $targetHost = if ($cmd.TargetHostname) { $cmd.TargetHostname } else { "ALL" }
                
                if ($targetHost -eq "ALL" -or $targetHost -eq $hostname) {
                    $pendingCommands += $cmd
                    Write-Log ">>> COMMANDE POUR NOUS: $($cmd.CommandType) v$($cmd.TargetVersion) <<<" "SUCCESS"
                }
            }
        }
        
        Write-Log ">>> $($pendingCommands.Count) commande(s) PENDING pour ce serveur <<<" "UPDATE"
        
        foreach ($cmd in $pendingCommands) {
            $cmdType = if ($cmd.CommandType) { $cmd.CommandType } else { "" }
            
            if ($cmdType -eq "UPDATE_ALL" -or $cmdType -eq "UPDATE") {
                Write-Log ">>> UPDATE DETECTE vers v$($cmd.TargetVersion) <<<" "SUCCESS"
                Write-Log ">>> AUTO-UPDATE FONCTIONNEL ! <<<" "SUCCESS"
                
                $newVersion = if ($cmd.TargetVersion) { $cmd.TargetVersion } else { "8.6" }
                
                Write-Log "Telechargement v$newVersion..." "UPDATE"
                $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$newVersion.ps1"
                $newAgentPath = "C:\SYAGA-ATLAS\agent_new.ps1"
                
                try {
                    Invoke-WebRequest -Uri $newAgentUrl -OutFile $newAgentPath -UseBasicParsing
                    
                    if (Test-Path $newAgentPath) {
                        Write-Log "Agent telecharge OK" "SUCCESS"
                        
                        Copy-Item "C:\SYAGA-ATLAS\agent.ps1" "C:\SYAGA-ATLAS\agent_backup.ps1" -Force
                        Move-Item $newAgentPath "C:\SYAGA-ATLAS\agent.ps1" -Force
                        
                        Write-Log ">>> MISE A JOUR REUSSIE vers v$newVersion <<<" "SUCCESS"
                        Write-Log ">>> L'AUTO-UPDATE MARCHE ENFIN ! <<<" "SUCCESS"
                        
                        # Marquer DONE
                        if ($cmd.Id) {
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
                            
                            try {
                                Invoke-RestMethod -Uri $updateUrl -Headers $updateHeaders -Method POST -Body $updateBody
                                Write-Log "Commande marquee DONE" "SUCCESS"
                            } catch {
                                Write-Log "Erreur marquage DONE: $_" "WARNING"
                            }
                        }
                        
                        Write-Log "REDEMARRAGE DANS 5 SECONDES..." "WARNING"
                        Start-Sleep -Seconds 5
                        exit 0
                    }
                } catch {
                    Write-Log "Erreur telechargement: $_" "ERROR"
                }
            }
        }
        
        if ($pendingCommands.Count -eq 0) {
            Write-Log "Aucune commande PENDING trouvee" "INFO"
        }
        
    } catch {
        Write-Log "Erreur check update: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT
# ════════════════════════════════════════════════════
function Send-HeartbeatWithLogs {
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
        
        # COLLECTER LES VRAIES METRIQUES
        
        # CPU
        $cpu = Get-WmiObject -Class Win32_Processor
        $cpuUsage = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average)
        
        # MEMOIRE
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $memTotal = $os.TotalVisibleMemorySize
        $memFree = $os.FreePhysicalMemory
        $memUsage = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)
        
        # DISQUE
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        
        # IP
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        Write-Log "Metriques: CPU=$cpuUsage% MEM=$memUsage% DISK=$diskFreeGB GB" "INFO"
        
        # Vérifier existence
        $searchUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items?`$filter=Hostname eq '$hostname'"
        $existing = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        
        # Nettoyer logs
        $cleanLogs = $script:LogsBuffer -replace '[^\x20-\x7E\r\n]', ' '
        
        # DONNEES AVEC LES VRAIS NOMS DE CHAMPS
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            IPAddress = $ip
            State = "ONLINE"
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = $script:Version
            CPUUsage = $cpuUsage
            MemoryUsage = $memUsage
            DiskSpaceGB = $diskFreeGB
            Logs = $cleanLogs
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
            Write-Log "Heartbeat + Logs OK" "SUCCESS"
        } else {
            # Create
            $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
            
            Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
            Write-Log "Heartbeat + Logs crees" "SUCCESS"
        }
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host "  ATLAS AGENT v$($script:Version) - FIX ÉCHAPPEMENT URL" -ForegroundColor Cyan  
Write-Host "===============================================================" -ForegroundColor Cyan
Write-Host ""

# Installation
if ($args -contains "-Install") {
    Write-Log "Installation agent v$($script:Version)..." "UPDATE"
    
    New-Item -ItemType Directory -Path "C:\SYAGA-ATLAS" -Force | Out-Null
    Copy-Item $MyInvocation.MyCommand.Path "C:\SYAGA-ATLAS\agent.ps1" -Force
    
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue
    
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\SYAGA-ATLAS\agent.ps1`""
    
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) `
        -RepetitionInterval (New-TimeSpan -Minutes 1)
    
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask "SYAGA-ATLAS-Agent" -Action $action -Trigger $trigger -Principal $principal | Out-Null
    
    Write-Log "Installation OK" "SUCCESS"
    
    Send-HeartbeatWithLogs
    exit 0
}

# Execution
Write-Log "Agent v$($script:Version) demarre" "INFO"
Write-Log ">>> FIX ÉCHAPPEMENT $ DANS URL <<<" "SUCCESS"

Check-AutoUpdate
Send-HeartbeatWithLogs

Write-Log "Fin execution" "SUCCESS"