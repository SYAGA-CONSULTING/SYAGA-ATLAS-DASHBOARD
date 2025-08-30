# ATLAS AGENT v0.16 - MÉTRIQUES DE BASE RÉELLES
# NOUVEAUTÉ v0.16: Remplace hardcoding par vraies métriques CPU/RAM/Disk
param([switch]$Install)

$VERSION = "v0.16"

if ($Install) {
    Write-Host "Installation Agent $VERSION..." -ForegroundColor Green
    Write-Host "Nouveauté: Vraies métriques CPU/RAM/Disk" -ForegroundColor Cyan
    
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    schtasks.exe /Create /TN "ATLAS-Monitor" /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\temp\agent-latest.ps1" /SC MINUTE /MO 2 /RU SYSTEM /RL HIGHEST /F
    Start-ScheduledTask -TaskName "ATLAS-Monitor"
    
    Write-Host "Agent $VERSION avec vraies métriques installé" -ForegroundColor Green
    exit 0
}

# EXECUTION
Write-Host "Agent $VERSION - Collecte métriques réelles..." -ForegroundColor Cyan

try {
    # Config
    $config = Get-Content "C:\ATLAS\config.json" | ConvertFrom-Json
    
    # Token
    $body = @{
        client_id = $config.ClientId
        scope = "https://graph.microsoft.com/.default"
        client_secret = $config.ClientSecret
        grant_type = "client_credentials"
    }
    $token = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($config.TenantId)/oauth2/v2.0/token" -Body $body).access_token
    $headers = @{ "Authorization" = "Bearer $token" }
    
    # AUTO-UPDATE - Vérifier nouvelle version
    Write-Host "Check auto-update..." -ForegroundColor Yellow
    $downloadUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com/drive/root:/ATLAS/atlas-agent-current.ps1:/content"
    $latestAgent = Invoke-RestMethod -Uri $downloadUrl -Headers $headers -Method GET
    
    # Extraire la version du nouvel agent
    if ($latestAgent -match '\$VERSION\s*=\s*"([^"]+)"') {
        $latestVersion = $matches[1]
        Write-Host "Version disponible: $latestVersion" -ForegroundColor Yellow
        Write-Host "Version actuelle: $VERSION" -ForegroundColor Yellow
        
        if ($latestVersion -ne $VERSION) {
            Write-Host "NOUVELLE VERSION DETECTEE!" -ForegroundColor Green
            Write-Host "Mise à jour $VERSION -> $latestVersion" -ForegroundColor Cyan
            
            # Sauvegarder et executer
            $latestAgent | Out-File "C:\temp\agent-latest.ps1" -Encoding UTF8 -Force
            Write-Host "Lancement installation nouvelle version..." -ForegroundColor Yellow
            & "C:\temp\agent-latest.ps1" -Install
            
            Write-Host "Auto-update terminé! Nouvelle version installée." -ForegroundColor Green
            exit 0
        } else {
            Write-Host "Déjà à jour ($VERSION)" -ForegroundColor Green
        }
    }
    
    Write-Host "=== COLLECTE MÉTRIQUES DE BASE v0.16 ===" -ForegroundColor Cyan
    
    # CATÉGORIE 1: MÉTRIQUES DE BASE RÉELLES
    
    # 1.1 CPU Usage réel
    Write-Host "Collecte CPU..." -ForegroundColor Yellow
    $cpuUsage = 0
    try {
        $cpu = Get-Counter -Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 3 -ErrorAction SilentlyContinue
        $cpuUsage = [Math]::Round(($cpu.CounterSamples | Measure-Object CookedValue -Average).Average, 1)
        Write-Host "CPU: $cpuUsage%" -ForegroundColor Green
    } catch {
        $cpuUsage = -1
        Write-Host "CPU: Erreur collecte" -ForegroundColor Red
    }
    
    # 1.2 RAM Usage réel
    Write-Host "Collecte RAM..." -ForegroundColor Yellow
    $memoryUsage = 0
    try {
        $totalRAM = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        $availableRAM = (Get-Counter -Counter "\Memory\Available MBytes" -ErrorAction SilentlyContinue).CounterSamples.CookedValue / 1024
        $usedRAM = $totalRAM - $availableRAM
        $memoryUsage = [Math]::Round(($usedRAM / $totalRAM) * 100, 1)
        Write-Host "RAM: $memoryUsage% ($([Math]::Round($usedRAM, 1))GB/$([Math]::Round($totalRAM, 1))GB)" -ForegroundColor Green
    } catch {
        $memoryUsage = -1
        Write-Host "RAM: Erreur collecte" -ForegroundColor Red
    }
    
    # 1.3 Disk Space réel (Drive C:)
    Write-Host "Collecte Disque C:..." -ForegroundColor Yellow
    $diskSpaceGB = 0
    $diskUsagePercent = 0
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($disk) {
            $totalGB = [Math]::Round($disk.Size / 1GB, 1)
            $freeGB = [Math]::Round($disk.FreeSpace / 1GB, 1)
            $usedGB = $totalGB - $freeGB
            $diskSpaceGB = $freeGB
            $diskUsagePercent = [Math]::Round(($usedGB / $totalGB) * 100, 1)
            Write-Host "Disque C: $diskUsagePercent% utilisé ($usedGB/$totalGB GB) - Libre: $freeGB GB" -ForegroundColor Green
        } else {
            $diskSpaceGB = -1
            Write-Host "Disque C: Non trouvé" -ForegroundColor Red
        }
    } catch {
        $diskSpaceGB = -1
        Write-Host "Disque C: Erreur collecte" -ForegroundColor Red
    }
    
    # 1.4 Uptime système
    Write-Host "Collecte Uptime..." -ForegroundColor Yellow
    $uptime = ""
    try {
        $bootTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
        if ($bootTime) {
            $uptime = (Get-Date) - $bootTime
            $uptimeStr = "$($uptime.Days)j $($uptime.Hours)h $($uptime.Minutes)m"
            Write-Host "Uptime: $uptimeStr" -ForegroundColor Green
        }
    } catch {
        $uptime = "Erreur"
        Write-Host "Uptime: Erreur collecte" -ForegroundColor Red
    }
    
    # Hyper-V (existant - pas modifié)
    $hyperVStatus = "N/A"
    try {
        $hyperVFeature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue
        if ($hyperVFeature -and $hyperVFeature.InstallState -eq "Installed") {
            $vms = @(Get-VM -ErrorAction SilentlyContinue)
            if ($vms) {
                $running = @($vms | Where-Object { $_.State -eq "Running" }).Count
                $hyperVStatus = "OK($running/$($vms.Count))"
            } else {
                $hyperVStatus = "OK(0VM)"
            }
        }
    } catch {}
    
    # Données avec vraies métriques
    $data = @{
        Title = $env:COMPUTERNAME
        Hostname = $env:COMPUTERNAME
        AgentVersion = $VERSION
        LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        State = "OK"
        HyperVStatus = $hyperVStatus
        CPUUsage = [double]$cpuUsage
        MemoryUsage = [double]$memoryUsage
        DiskSpaceGB = [double]$diskSpaceGB
        VeeamStatus = "$VERSION-REAL-METRICS"
    }
    
    # Log dans ATLAS_LOGS
    $logData = @{
        fields = @{
            Title = "Collecte-v0.16-$(Get-Date -Format 'HHmmss')"
            Hostname = $env:COMPUTERNAME
            Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            Level = "INFO"
            Source = "MetricsCollector"
            Message = "Métriques v0.16 collectées: CPU=$cpuUsage%, RAM=$memoryUsage%, Disk=$diskSpaceGB GB"
            Details = "Uptime: $uptimeStr"
        }
    }
    
    # Envoyer log
    $logsUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/bd8d22c0-a9dc-4116-9a29-a590b429826e/items"
    try {
        Invoke-RestMethod -Uri $logsUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($logData | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Log envoyé vers ATLAS_LOGS" -ForegroundColor Green
    } catch {
        Write-Host "Erreur envoi log: $_" -ForegroundColor Yellow
    }
    
    # Envoyer à ATLAS-Servers
    $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
    
    $existingUrl = "$listUrl`?`$expand=fields"
    $existing = Invoke-RestMethod -Uri $existingUrl -Headers $headers
    
    $myItem = $existing.value | Where-Object { $_.fields.Hostname -eq $env:COMPUTERNAME }
    
    if ($myItem) {
        # Mise à jour
        $updateUrl = "$listUrl/$($myItem.id)"
        $updateData = @{ fields = $data }
        Invoke-RestMethod -Uri $updateUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method PATCH -Body ($updateData | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Métriques v0.16 mises à jour dans SharePoint" -ForegroundColor Green
    } else {
        # Création
        $createData = @{ fields = $data }
        Invoke-RestMethod -Uri $listUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($createData | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Nouveau serveur v0.16 créé dans SharePoint" -ForegroundColor Green
    }
    
} catch {
    Write-Host "Erreur: $_" -ForegroundColor Red
    
    # Log d'erreur
    try {
        $errorLogData = @{
            fields = @{
                Title = "ERROR-v0.16-$(Get-Date -Format 'HHmmss')"
                Hostname = $env:COMPUTERNAME
                Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                Level = "ERROR"
                Source = "Agent"
                Message = "Erreur agent v0.16: $_"
                Details = $_.ScriptStackTrace
            }
        }
        
        $logsUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/bd8d22c0-a9dc-4116-9a29-a590b429826e/items"
        $token = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$((Get-Content 'C:\ATLAS\config.json' | ConvertFrom-Json).TenantId)/oauth2/v2.0/token" -Body @{client_id=(Get-Content 'C:\ATLAS\config.json' | ConvertFrom-Json).ClientId;scope="https://graph.microsoft.com/.default";client_secret=(Get-Content 'C:\ATLAS\config.json' | ConvertFrom-Json).ClientSecret;grant_type="client_credentials"}).access_token
        
        Invoke-RestMethod -Uri $logsUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($errorLogData | ConvertTo-Json -Depth 5) | Out-Null
    } catch {}
}

Write-Host "Agent $VERSION terminé." -ForegroundColor Green