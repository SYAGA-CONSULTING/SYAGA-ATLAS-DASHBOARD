# ATLAS AGENT v0.18 - VEEAM BACKUP DÉTAILLÉ
# NOUVEAUTÉ v0.18: Métriques Veeam complètes (Jobs, Status, Last Backup, Storage)
param([switch]$Install)

$VERSION = "v0.18"

if ($Install) {
    Write-Host "Installation Agent $VERSION..." -ForegroundColor Green
    Write-Host "Nouveauté: Veeam Backup détaillé" -ForegroundColor Cyan
    
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    schtasks.exe /Create /TN "ATLAS-Monitor" /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\temp\agent-latest.ps1" /SC MINUTE /MO 2 /RU SYSTEM /RL HIGHEST /F
    Start-ScheduledTask -TaskName "ATLAS-Monitor"
    
    Write-Host "Agent $VERSION avec Veeam détaillé installé" -ForegroundColor Green
    exit 0
}

# EXECUTION
Write-Host "Agent $VERSION - Collecte Veeam détaillée..." -ForegroundColor Cyan

try {
    # Config et Token (identique)
    $config = Get-Content "C:\ATLAS\config.json" | ConvertFrom-Json
    
    $body = @{
        client_id = $config.ClientId
        scope = "https://graph.microsoft.com/.default"
        client_secret = $config.ClientSecret
        grant_type = "client_credentials"
    }
    $token = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($config.TenantId)/oauth2/v2.0/token" -Body $body).access_token
    $headers = @{ "Authorization" = "Bearer $token" }
    
    # AUTO-UPDATE
    Write-Host "Check auto-update..." -ForegroundColor Yellow
    $downloadUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com/drive/root:/ATLAS/atlas-agent-current.ps1:/content"
    $latestAgent = Invoke-RestMethod -Uri $downloadUrl -Headers $headers -Method GET
    
    if ($latestAgent -match '\$VERSION\s*=\s*"([^"]+)"') {
        $latestVersion = $matches[1]
        if ($latestVersion -ne $VERSION) {
            Write-Host "NOUVELLE VERSION: $latestVersion" -ForegroundColor Green
            $latestAgent | Out-File "C:\temp\agent-latest.ps1" -Encoding UTF8 -Force
            & "C:\temp\agent-latest.ps1" -Install
            exit 0
        }
    }
    
    Write-Host "=== COLLECTE v0.18 VEEAM ===" -ForegroundColor Cyan
    
    # IP ADDRESS (v0.17.1)
    Write-Host "Collecte IP..." -ForegroundColor Yellow
    $ipAddress = "N/A"
    try {
        $networkAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notlike "*Loopback*" } | Select-Object -First 1
        if ($networkAdapter) {
            $ip = Get-NetIPAddress -InterfaceIndex $networkAdapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
            if ($ip) {
                $ipAddress = $ip.IPAddress
            }
        }
    } catch {
        $ipAddress = "Error"
    }
    
    # MÉTRIQUES DE BASE (v0.16/v0.17)
    $cpuUsage = 0
    try {
        $cpu = Get-Counter -Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 3 -ErrorAction SilentlyContinue
        $cpuUsage = [Math]::Round(($cpu.CounterSamples | Measure-Object CookedValue -Average).Average, 1)
    } catch { $cpuUsage = -1 }
    
    $memoryUsage = 0
    try {
        $totalRAM = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        $availableRAM = (Get-Counter -Counter "\Memory\Available MBytes" -ErrorAction SilentlyContinue).CounterSamples.CookedValue / 1024
        $usedRAM = $totalRAM - $availableRAM
        $memoryUsage = [Math]::Round(($usedRAM / $totalRAM) * 100, 1)
    } catch { $memoryUsage = -1 }
    
    $diskSpaceGB = 0
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($disk) {
            $diskSpaceGB = [Math]::Round($disk.FreeSpace / 1GB, 1)
        }
    } catch { $diskSpaceGB = -1 }
    
    # HYPER-V (v0.17 simplifié)
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
    
    # CATÉGORIE 3: VEEAM BACKUP DÉTAILLÉ
    Write-Host "=== VEEAM BACKUP DÉTAILLÉ v0.18 ===" -ForegroundColor Cyan
    
    $veeamStatus = "N/A"
    $veeamDetails = @()
    $backupJobsCount = 0
    $lastBackupDate = "N/A"
    $backupSizeGB = 0
    
    try {
        # Vérifier si Veeam est installé
        $veeamInstalled = $false
        
        # Méthode 1: Vérifier le service Veeam
        $veeamService = Get-Service -Name "Veeam*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($veeamService) {
            $veeamInstalled = $true
            Write-Host "Veeam détecté via service: $($veeamService.Name)" -ForegroundColor Green
        }
        
        # Méthode 2: Vérifier l'installation via registre
        if (!$veeamInstalled) {
            $veeamReg = Get-ItemProperty "HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication" -ErrorAction SilentlyContinue
            if ($veeamReg) {
                $veeamInstalled = $true
                Write-Host "Veeam détecté via registre" -ForegroundColor Green
            }
        }
        
        # Méthode 3: Vérifier PowerShell Snap-in Veeam
        if (!$veeamInstalled) {
            $veeamSnapin = Get-PSSnapin -Registered | Where-Object { $_.Name -like "*Veeam*" }
            if ($veeamSnapin) {
                $veeamInstalled = $true
                Add-PSSnapin $veeamSnapin.Name -ErrorAction SilentlyContinue
                Write-Host "Veeam Snap-in chargé: $($veeamSnapin.Name)" -ForegroundColor Green
            }
        }
        
        if ($veeamInstalled) {
            Write-Host "Analyse Veeam Backup..." -ForegroundColor Yellow
            
            # Essayer de charger le module Veeam PowerShell
            try {
                # Pour Veeam v11+
                Import-Module "C:\Program Files\Veeam\Backup and Replication\Console\Veeam.Backup.PowerShell.dll" -ErrorAction SilentlyContinue
            } catch {
                # Pour versions plus anciennes
                Add-PSSnapin VeeamPSSnapin -ErrorAction SilentlyContinue
            }
            
            # Récupérer les jobs Veeam
            try {
                $jobs = @(Get-VBRJob -ErrorAction SilentlyContinue)
                $backupJobsCount = $jobs.Count
                Write-Host "Jobs Veeam trouvés: $backupJobsCount" -ForegroundColor Green
                
                if ($jobs.Count -gt 0) {
                    $successJobs = @($jobs | Where-Object { $_.GetLastResult() -eq "Success" }).Count
                    $warningJobs = @($jobs | Where-Object { $_.GetLastResult() -eq "Warning" }).Count
                    $failedJobs = @($jobs | Where-Object { $_.GetLastResult() -eq "Failed" }).Count
                    
                    $veeamStatus = "Jobs:$backupJobsCount OK:$successJobs W:$warningJobs F:$failedJobs"
                    
                    # Analyser chaque job
                    foreach ($job in $jobs | Select-Object -First 5) {
                        try {
                            $lastSession = $job.GetLastSession()
                            $jobDetail = @{
                                Name = $job.Name
                                Type = $job.JobType
                                LastRun = if ($lastSession) { $lastSession.CreationTime } else { "Never" }
                                LastResult = $job.GetLastResult()
                                NextRun = $job.GetScheduleOptions().NextRun
                                IsEnabled = $job.IsScheduleEnabled
                            }
                            
                            $veeamDetails += $jobDetail
                            
                            # Dernière date de backup
                            if ($lastSession -and $lastSession.CreationTime -gt $lastBackupDate) {
                                $lastBackupDate = $lastSession.CreationTime
                            }
                            
                        } catch {
                            Write-Host "Erreur analyse job $($job.Name): $_" -ForegroundColor Yellow
                        }
                    }
                    
                    # Taille totale des backups
                    try {
                        $repositories = Get-VBRBackupRepository -ErrorAction SilentlyContinue
                        foreach ($repo in $repositories) {
                            $backups = Get-VBRBackup -Repository $repo -ErrorAction SilentlyContinue
                            foreach ($backup in $backups) {
                                $backupSizeGB += [Math]::Round($backup.GetSize() / 1GB, 1)
                            }
                        }
                        Write-Host "Taille totale backups: $backupSizeGB GB" -ForegroundColor Green
                    } catch {
                        Write-Host "Impossible de calculer taille backups" -ForegroundColor Yellow
                    }
                    
                } else {
                    $veeamStatus = "Installed(NoJobs)"
                }
                
            } catch {
                $veeamStatus = "Installed(NoAccess)"
                Write-Host "Veeam installé mais pas d'accès aux jobs: $_" -ForegroundColor Yellow
            }
            
        } else {
            $veeamStatus = "NotInstalled"
            Write-Host "Veeam non détecté sur ce serveur" -ForegroundColor Yellow
        }
        
    } catch {
        $veeamStatus = "Error: $_"
        Write-Host "Erreur Veeam: $_" -ForegroundColor Red
    }
    
    # Données pour ATLAS-Servers
    $data = @{
        Title = $env:COMPUTERNAME
        Hostname = $env:COMPUTERNAME
        IPAddress = $ipAddress
        AgentVersion = $VERSION
        LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        State = "OK"
        HyperVStatus = $hyperVStatus
        CPUUsage = [double]$cpuUsage
        MemoryUsage = [double]$memoryUsage
        DiskSpaceGB = [double]$diskSpaceGB
        VeeamStatus = $veeamStatus
    }
    
    # Log principal Veeam
    $logMessage = "v0.18: Veeam: $veeamStatus | Jobs: $backupJobsCount | Size: $($backupSizeGB)GB | LastBackup: $lastBackupDate"
    $logData = @{
        fields = @{
            Title = "Veeam-v0.18-$(Get-Date -Format 'HHmmss')"
            Hostname = $env:COMPUTERNAME
            Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            Level = "INFO"
            Source = "VeeamCollector"
            Message = $logMessage
            Details = "IP: $ipAddress"
        }
    }
    
    # Envoyer logs
    $logsUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/bd8d22c0-a9dc-4116-9a29-a590b429826e/items"
    try {
        Invoke-RestMethod -Uri $logsUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($logData | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Log Veeam envoyé" -ForegroundColor Green
    } catch {}
    
    # Logs détaillés par job Veeam
    foreach ($jobDetail in $veeamDetails | Select-Object -First 3) {
        try {
            $jobLogData = @{
                fields = @{
                    Title = "VeeamJob-$($jobDetail.Name)-$(Get-Date -Format 'HHmmss')"
                    Hostname = $env:COMPUTERNAME
                    Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                    Level = if ($jobDetail.LastResult -eq "Success") { "INFO" } elseif ($jobDetail.LastResult -eq "Warning") { "WARN" } else { "ERROR" }
                    Source = "VeeamJob"
                    Message = "Job $($jobDetail.Name): $($jobDetail.LastResult) | Type: $($jobDetail.Type) | LastRun: $($jobDetail.LastRun)"
                    Details = "NextRun: $($jobDetail.NextRun) | Enabled: $($jobDetail.IsEnabled)"
                }
            }
            Invoke-RestMethod -Uri $logsUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($jobLogData | ConvertTo-Json -Depth 5) | Out-Null
        } catch {}
    }
    
    # Envoyer à ATLAS-Servers
    $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
    
    $existingUrl = "$listUrl`?`$expand=fields"
    $existing = Invoke-RestMethod -Uri $existingUrl -Headers $headers
    $myItem = $existing.value | Where-Object { $_.fields.Hostname -eq $env:COMPUTERNAME }
    
    if ($myItem) {
        $updateUrl = "$listUrl/$($myItem.id)"
        $updateData = @{ fields = $data }
        Invoke-RestMethod -Uri $updateUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method PATCH -Body ($updateData | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Métriques v0.18 Veeam mises à jour" -ForegroundColor Green
    } else {
        $createData = @{ fields = $data }
        Invoke-RestMethod -Uri $listUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($createData | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Nouveau serveur v0.18 créé" -ForegroundColor Green
    }
    
} catch {
    Write-Host "Erreur: $_" -ForegroundColor Red
    
    # Log d'erreur
    try {
        $errorLogData = @{
            fields = @{
                Title = "ERROR-v0.18-$(Get-Date -Format 'HHmmss')"
                Hostname = $env:COMPUTERNAME
                Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                Level = "ERROR"
                Source = "Agent"
                Message = "Erreur agent v0.18: $_"
                Details = $_.ScriptStackTrace
            }
        }
        
        $logsUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/bd8d22c0-a9dc-4116-9a29-a590b429826e/items"
        Invoke-RestMethod -Uri $logsUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($errorLogData | ConvertTo-Json -Depth 5) | Out-Null
    } catch {}
}

Write-Host "Agent $VERSION terminé." -ForegroundColor Green