# ATLAS Agent v8.2 - FIX REQUÊTE AUTO-UPDATE
$script:Version = "8.2"
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
# FONCTION CHECK AUTO-UPDATE (FIXÉE)
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
        
        # REQUÊTE FIXÉE - Sans filtre complexe d'abord
        Write-Log "Recherche commandes UPDATE..." "DEBUG"
        
        # Récupérer TOUTES les commandes et filtrer localement
        $searchUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items?`$select=Id,Title,CommandType,Status,TargetVersion,TargetHostname&`$orderby=Created desc&`$top=50"
        
        Write-Log "URL: $searchUrl" "DEBUG"
        
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET
        $allCommands = $response.d.results
        
        Write-Log "Total commandes dans la liste: $($allCommands.Count)" "DEBUG"
        
        # Filtrer localement
        $commands = @()
        foreach ($cmd in $allCommands) {
            if ($cmd.Status -eq "PENDING") {
                if ($cmd.TargetHostname -eq "ALL" -or $cmd.TargetHostname -eq $hostname) {
                    $commands += $cmd
                    Write-Log "Commande trouvee: $($cmd.CommandType) v$($cmd.TargetVersion) pour $($cmd.TargetHostname)" "DEBUG"
                }
            }
        }
        
        Write-Log ">>> $($commands.Count) commande(s) PENDING pour ce serveur <<<" "UPDATE"
        
        foreach ($cmd in $commands) {
            if ($cmd.CommandType -eq "UPDATE_ALL" -or $cmd.CommandType -eq "UPDATE") {
                Write-Log ">>> UPDATE DETECTE vers v$($cmd.TargetVersion) <<<" "SUCCESS"
                
                $newVersion = if ($cmd.TargetVersion) { $cmd.TargetVersion } else { "8.2" }
                
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
                        
                        Write-Log "REDEMARRAGE DANS 5 SECONDES..." "WARNING"
                        Start-Sleep -Seconds 5
                        exit 0
                    }
                } catch {
                    Write-Log "Erreur: $_" "ERROR"
                }
            }
        }
        
    } catch {
        Write-Log "Erreur: $_" "ERROR"
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
Write-Host "  ATLAS AGENT v$($script:Version) - FIX AUTO-UPDATE" -ForegroundColor Cyan  
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

Check-AutoUpdate
Send-HeartbeatWithLogs

Write-Log "Fin execution" "SUCCESS"