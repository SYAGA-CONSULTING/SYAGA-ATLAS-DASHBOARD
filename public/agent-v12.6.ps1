# ATLAS Agent v12.6 - LOGS ENRICHIS + AUTO-FIX + TRACKING
$script:Version = "12.6"
$hostname = $env:COMPUTERNAME
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

# Buffer logs enrichis
$script:LogsBuffer = ""
$script:MaxBufferSize = 15000  # Plus grand pour plus de logs

# ════════════════════════════════════════════════════
# FONCTION LOG ENRICHIE
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Buffer
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxBufferSize) {
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $script:MaxBufferSize)
    }
    
    # Afficher
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        "DEBUG" { Write-Host $logEntry -ForegroundColor Cyan }
        default { Write-Host $logEntry }
    }
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# FONCTION POUR OBTENIR L'ACTIVITÉ DE L'UPDATER
# ════════════════════════════════════════════════════
function Get-UpdaterActivity {
    $updaterInfo = @{
        LastRun = "Never"
        Version = "Unknown"
        Status = "Unknown"
        LastCommand = "None"
    }
    
    try {
        # Vérifier le log de l'updater
        $updaterLogPath = "C:\SYAGA-ATLAS\updater_log.txt"
        if (Test-Path $updaterLogPath) {
            # Obtenir la dernière modification du fichier
            $lastModified = (Get-Item $updaterLogPath).LastWriteTime
            $updaterInfo.LastRun = $lastModified.ToString("yyyy-MM-dd HH:mm:ss")
            
            # Lire les dernières lignes pour avoir la version et commande
            $lastLines = Get-Content $updaterLogPath -Tail 30
            foreach ($line in $lastLines) {
                if ($line -match "UPDATER v([\d\.]+)") {
                    $updaterInfo.Version = $matches[1]
                }
                if ($line -match "COMMANDE.*ID.*(\d+).*v([\d\.]+)") {
                    $updaterInfo.LastCommand = "ID=$($matches[1]) v$($matches[2])"
                }
            }
            
            # Vérifier si actif (modifié dans les 5 dernières minutes)
            $timeDiff = (Get-Date) - $lastModified
            if ($timeDiff.TotalMinutes -lt 5) {
                $updaterInfo.Status = "ACTIVE"
            } elseif ($timeDiff.TotalMinutes -lt 15) {
                $updaterInfo.Status = "RECENT"
            } else {
                $updaterInfo.Status = "INACTIVE"
            }
        }
        
        # Vérifier la tâche planifiée
        $task = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
        if ($task) {
            $updaterInfo.TaskState = $task.State
        }
        
    } catch {
        Write-Log "Erreur lecture updater: $_" "WARNING"
    }
    
    return $updaterInfo
}

# ════════════════════════════════════════════════════
# v12.6: AUTO-FIX UPDATER (de v12.5)
# ════════════════════════════════════════════════════
function Fix-Updater {
    Write-Log "=== AUTO-FIX UPDATER ===" "UPDATE"
    
    $updaterPath = "C:\SYAGA-ATLAS\updater.ps1"
    $needsUpdate = $false
    
    # Vérifier version updater
    if (Test-Path $updaterPath) {
        $updaterContent = Get-Content $updaterPath -Raw
        if ($updaterContent -match 'Version\s*=\s*"([^"]+)"') {
            $updaterVersion = $matches[1]
            Write-Log "Updater actuel: v$updaterVersion" "INFO"
            
            # Si updater < 12.4, le mettre à jour
            if ($updaterVersion -lt "12.4") {
                $needsUpdate = $true
                Write-Log "Updater obsolète (<12.4), mise à jour nécessaire" "WARNING"
            } else {
                Write-Log "Updater OK (v$updaterVersion >= 12.4)" "SUCCESS"
            }
        } else {
            $needsUpdate = $true
            Write-Log "Version updater inconnue" "WARNING"
        }
    } else {
        $needsUpdate = $true
        Write-Log "Updater introuvable!" "ERROR"
    }
    
    if ($needsUpdate) {
        Write-Log "Installation updater v12.4..." "UPDATE"
        
        try {
            $updaterUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v12.4.ps1"
            
            # Backup si existe
            if (Test-Path $updaterPath) {
                $backupPath = "C:\SYAGA-ATLAS\updater_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
                Copy-Item $updaterPath $backupPath -Force
                Write-Log "Backup créé: $backupPath" "INFO"
            }
            
            # Télécharger nouvel updater
            Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
            
            if (Test-Path $updaterPath) {
                Write-Log "Updater v12.4 installé avec succès" "SUCCESS"
                
                # Exécuter l'updater pour qu'il vérifie les mises à jour
                Write-Log "Exécution updater pour vérification..." "UPDATE"
                Start-Process powershell -ArgumentList "-File", $updaterPath -NoNewWindow -Wait
                
                Write-Log "AUTO-FIX terminé" "SUCCESS"
            }
        } catch {
            Write-Log "Erreur AUTO-FIX: $_" "ERROR"
        }
    }
    
    Write-Log "=== FIN AUTO-FIX ===" "UPDATE"
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT AVEC LOGS ENRICHIS
# ════════════════════════════════════════════════════
function Send-HeartbeatWithTracking {
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
        
        # Métriques système
        Write-Log "Collecte métriques système..." "DEBUG"
        
        $cpu = Get-WmiObject -Class Win32_Processor
        $cpuUsage = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average)
        
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $memTotal = $os.TotalVisibleMemorySize
        $memFree = $os.FreePhysicalMemory
        $memUsage = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)
        
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $diskTotalGB = [math]::Round($disk.Size / 1GB, 1)
        
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        Write-Log "CPU=$cpuUsage% MEM=$memUsage% ($('{0:N1}' -f (($memTotal - $memFree)/1024))MB used) DISK=$diskFreeGB/$diskTotalGB GB" "INFO"
        
        # Obtenir info updater
        Write-Log "Vérification activité updater..." "DEBUG"
        $updaterInfo = Get-UpdaterActivity
        
        Write-Log "Updater: v$($updaterInfo.Version) - $($updaterInfo.Status) - Last: $($updaterInfo.LastRun)" "INFO"
        if ($updaterInfo.LastCommand -ne "None") {
            Write-Log "Dernière commande updater: $($updaterInfo.LastCommand)" "INFO"
        }
        
        # Créer header enrichi pour les logs
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logHeader = @"
════════════════════════════════════════════════════
ATLAS v$($script:Version) MONITORING REPORT
════════════════════════════════════════════════════
Hostname: $hostname
IP: $ip
Time: $currentTime

AGENT STATUS:
  Version: $($script:Version)
  Last Run: $currentTime
  Status: ACTIVE

UPDATER STATUS:
  Version: $($updaterInfo.Version)
  Last Run: $($updaterInfo.LastRun)
  Status: $($updaterInfo.Status)
  Last Command: $($updaterInfo.LastCommand)

SYSTEM METRICS:
  CPU Usage: $cpuUsage%
  Memory: $memUsage% ($('{0:N1}' -f (($memTotal - $memFree)/1024))MB / $('{0:N1}' -f ($memTotal/1024))MB)
  Disk C: $diskFreeGB GB free / $diskTotalGB GB total

RECENT LOGS:
════════════════════════════════════════════════════
"@
        
        # Ajouter les logs
        $enrichedLogs = $logHeader + "`r`n" + $script:LogsBuffer
        
        # Créer tracking pour le champ Notes
        $trackingNotes = "Agent:$currentTime|Updater:$($updaterInfo.LastRun)|UpdaterVer:$($updaterInfo.Version)|UpdaterStatus:$($updaterInfo.Status)"
        
        # DONNÉES avec logs enrichis et tracking
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
            Logs = $enrichedLogs
            Notes = $trackingNotes
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Créer nouvelle entrée
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Heartbeat envoyé avec logs enrichis" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════
Write-Log "" "INFO"
Write-Log "════════════════════════════════════════" "INFO"
Write-Log "Agent v$($script:Version) - LOGS ENRICHIS + TRACKING" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

# v12.6: Vérifier et corriger l'updater si nécessaire
Fix-Updater

# Envoyer heartbeat avec logs enrichis
Write-Log "Envoi heartbeat avec logs enrichis..." "UPDATE"
Send-HeartbeatWithTracking

Write-Log "════════════════════════════════════════" "INFO"
Write-Log "Fin agent v$($script:Version)" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"
exit 0