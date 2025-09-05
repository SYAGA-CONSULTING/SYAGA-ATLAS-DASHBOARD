# ATLAS Agent v12.5 - AUTO-FIX UPDATER
$script:Version = "12.5"
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

# Buffer logs
$script:LogsBuffer = ""

# ════════════════════════════════════════════════════
# FONCTION LOG
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt 8000) {
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - 8000)
    }
    
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
# v12.5: AUTO-FIX UPDATER
# ════════════════════════════════════════════════════
function Fix-Updater {
    Write-Log "Vérification updater..." "UPDATE"
    
    $updaterPath = "C:\SYAGA-ATLAS\updater.ps1"
    $needsUpdate = $false
    
    # Vérifier version updater
    if (Test-Path $updaterPath) {
        $updaterContent = Get-Content $updaterPath -Raw
        if ($updaterContent -match 'Version\s*=\s*"([^"]+)"') {
            $updaterVersion = $matches[1]
            Write-Log "Updater version: v$updaterVersion" "INFO"
            
            # Si updater < 12.4, le mettre à jour
            if ($updaterVersion -lt "12.4") {
                $needsUpdate = $true
                Write-Log "Updater obsolète, mise à jour nécessaire" "WARNING"
            }
        } else {
            $needsUpdate = $true
            Write-Log "Version updater inconnue" "WARNING"
        }
    } else {
        $needsUpdate = $true
        Write-Log "Updater introuvable" "ERROR"
    }
    
    if ($needsUpdate) {
        Write-Log "AUTO-FIX: Installation updater v12.4..." "UPDATE"
        
        try {
            $updaterUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v12.4.ps1"
            
            # Backup si existe
            if (Test-Path $updaterPath) {
                Copy-Item $updaterPath "C:\SYAGA-ATLAS\updater_old.ps1" -Force
            }
            
            # Télécharger nouvel updater
            Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
            
            if (Test-Path $updaterPath) {
                Write-Log "Updater v12.4 installé avec succès" "SUCCESS"
                
                # Exécuter l'updater pour qu'il installe la dernière version de l'agent
                Write-Log "Exécution updater pour mise à jour agent..." "UPDATE"
                Start-Process powershell -ArgumentList "-File", $updaterPath -NoNewWindow -Wait
                
                Write-Log "AUTO-FIX terminé" "SUCCESS"
                
                # Terminer cet agent car une nouvelle version devrait être installée
                exit 0
            }
        } catch {
            Write-Log "Erreur AUTO-FIX: $_" "ERROR"
        }
    } else {
        Write-Log "Updater OK (v$updaterVersion)" "SUCCESS"
    }
}

# ════════════════════════════════════════════════════
# FONCTION HEARTBEAT
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
        $cpu = Get-WmiObject -Class Win32_Processor
        $cpuUsage = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average)
        
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $memTotal = $os.TotalVisibleMemorySize
        $memFree = $os.FreePhysicalMemory
        $memUsage = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)
        
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        Write-Log "CPU=$cpuUsage% MEM=$memUsage% DISK=$diskFreeGB GB"
        
        # DONNÉES
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
            Logs = $script:LogsBuffer
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Créer nouvelle entrée
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        Write-Log "Heartbeat OK" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════
Write-Log "Agent v$($script:Version) - AUTO-FIX" "SUCCESS"

# v12.5: Vérifier et corriger l'updater
Fix-Updater

# Envoyer heartbeat
Send-Heartbeat

Write-Log "Fin agent v$($script:Version)"
exit 0