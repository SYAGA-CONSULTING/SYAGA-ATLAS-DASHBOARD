# ATLAS Agent v12.2-fix - SELF-UPDATE EMERGENCY
$script:Version = "12.2"
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

# Buffer simple
$script:LogsBuffer = ""

# ════════════════════════════════════════════════════
# FONCTION LOG SIMPLE
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt 5000) {
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - 5000)
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
# SELF UPDATE EMERGENCY
# ════════════════════════════════════════════════════
Write-Log "Agent v12.2 EMERGENCY FIX" "UPDATE"
Write-Log "Installation forcée updater v12.4..." "UPDATE"

try {
    # Installer updater v12.4 directement
    $updaterUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v12.4.ps1"
    $updaterPath = "C:\SYAGA-ATLAS\updater.ps1"
    
    Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
    Write-Log "Updater v12.4 téléchargé" "SUCCESS"
    
    # Installer agent v12.5 directement
    $agentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v12.5.ps1"
    $agentPath = "C:\SYAGA-ATLAS\agent.ps1"
    
    # Backup
    Copy-Item $agentPath "C:\SYAGA-ATLAS\agent_backup.ps1" -Force -ErrorAction SilentlyContinue
    
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing
    Write-Log "Agent v12.5 installé" "SUCCESS"
    
    Write-Log "SELF-UPDATE RÉUSSI!" "SUCCESS"
    
    # Relancer la tâche agent
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    
} catch {
    Write-Log "Erreur self-update: $_" "ERROR"
}

# Continuer avec heartbeat normal
function Send-Heartbeat {
    try {
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
        
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            IPAddress = $ip
            State = "ONLINE"
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = "12.2-fix"
            CPUUsage = $cpuUsage
            MemoryUsage = $memUsage
            DiskSpaceGB = $diskFreeGB
            Logs = $script:LogsBuffer
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        Write-Log "Heartbeat OK" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

Send-Heartbeat
Write-Log "Fin v12.2-fix"
exit 0