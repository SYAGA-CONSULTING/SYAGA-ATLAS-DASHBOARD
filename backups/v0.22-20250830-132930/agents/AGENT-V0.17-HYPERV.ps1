# ATLAS AGENT v0.17 - HYPER-V DÉTAILLÉ
# NOUVEAUTÉ v0.17: Métriques Hyper-V complètes (VMs, Réplication, Checkpoints)
param([switch]$Install)

$VERSION = "v0.17"

if ($Install) {
    Write-Host "Installation Agent $VERSION..." -ForegroundColor Green
    Write-Host "Nouveauté: Hyper-V détaillé + Réplication" -ForegroundColor Cyan
    
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    schtasks.exe /Create /TN "ATLAS-Monitor" /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\temp\agent-latest.ps1" /SC MINUTE /MO 2 /RU SYSTEM /RL HIGHEST /F
    Start-ScheduledTask -TaskName "ATLAS-Monitor"
    
    Write-Host "Agent $VERSION avec Hyper-V détaillé installé" -ForegroundColor Green
    exit 0
}

# EXECUTION
Write-Host "Agent $VERSION - Collecte Hyper-V détaillée..." -ForegroundColor Cyan

try {
    # Config et Token (identique v0.16)
    $config = Get-Content "C:\ATLAS\config.json" | ConvertFrom-Json
    
    $body = @{
        client_id = $config.ClientId
        scope = "https://graph.microsoft.com/.default"
        client_secret = $config.ClientSecret
        grant_type = "client_credentials"
    }
    $token = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($config.TenantId)/oauth2/v2.0/token" -Body $body).access_token
    $headers = @{ "Authorization" = "Bearer $token" }
    
    # AUTO-UPDATE (identique v0.16)
    Write-Host "Check auto-update..." -ForegroundColor Yellow
    $downloadUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com/drive/root:/ATLAS/atlas-agent-current.ps1:/content"
    $latestAgent = Invoke-RestMethod -Uri $downloadUrl -Headers $headers -Method GET
    
    if ($latestAgent -match '\$VERSION\s*=\s*"([^"]+)"') {
        $latestVersion = $matches[1]
        if ($latestVersion -ne $VERSION) {
            Write-Host "NOUVELLE VERSION DETECTEE: $latestVersion" -ForegroundColor Green
            $latestAgent | Out-File "C:\temp\agent-latest.ps1" -Encoding UTF8 -Force
            & "C:\temp\agent-latest.ps1" -Install
            exit 0
        }
    }
    
    Write-Host "=== COLLECTE MÉTRIQUES v0.17 ===" -ForegroundColor Cyan
    
    # MÉTRIQUES DE BASE (v0.16 - identique)
    Write-Host "Collecte CPU..." -ForegroundColor Yellow
    $cpuUsage = 0
    try {
        $cpu = Get-Counter -Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 3 -ErrorAction SilentlyContinue
        $cpuUsage = [Math]::Round(($cpu.CounterSamples | Measure-Object CookedValue -Average).Average, 1)
    } catch { $cpuUsage = -1 }
    
    Write-Host "Collecte RAM..." -ForegroundColor Yellow
    $memoryUsage = 0
    try {
        $totalRAM = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        $availableRAM = (Get-Counter -Counter "\Memory\Available MBytes" -ErrorAction SilentlyContinue).CounterSamples.CookedValue / 1024
        $usedRAM = $totalRAM - $availableRAM
        $memoryUsage = [Math]::Round(($usedRAM / $totalRAM) * 100, 1)
    } catch { $memoryUsage = -1 }
    
    Write-Host "Collecte Disque..." -ForegroundColor Yellow
    $diskSpaceGB = 0
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
        if ($disk) {
            $diskSpaceGB = [Math]::Round($disk.FreeSpace / 1GB, 1)
        }
    } catch { $diskSpaceGB = -1 }
    
    # CATÉGORIE 2: HYPER-V DÉTAILLÉ
    Write-Host "=== HYPER-V DÉTAILLÉ v0.17 ===" -ForegroundColor Cyan
    
    $hyperVStatus = "N/A"
    $hyperVDetails = @()
    $replicationStatus = "N/A"
    
    try {
        # Vérifier si Hyper-V est installé
        $hyperVFeature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue
        if ($hyperVFeature -and $hyperVFeature.InstallState -eq "Installed") {
            Write-Host "Hyper-V détecté - Analyse VMs..." -ForegroundColor Yellow
            
            # Récupérer toutes les VMs
            $vms = @(Get-VM -ErrorAction SilentlyContinue)
            
            if ($vms) {
                $running = @($vms | Where-Object { $_.State -eq "Running" }).Count
                $stopped = @($vms | Where-Object { $_.State -eq "Off" }).Count
                $paused = @($vms | Where-Object { $_.State -eq "Paused" }).Count
                $saved = @($vms | Where-Object { $_.State -eq "Saved" }).Count
                
                $hyperVStatus = "OK($running/$($vms.Count)) R:$running S:$stopped P:$paused Sv:$saved"
                
                Write-Host "VMs trouvées: $($vms.Count) | Running: $running | Stopped: $stopped" -ForegroundColor Green
                
                # Analyser chaque VM
                foreach ($vm in $vms) {
                    try {
                        $vmDetail = @{
                            Name = $vm.Name
                            State = $vm.State
                            CPUUsage = $vm.CPUUsage
                            MemoryAssigned = [Math]::Round($vm.MemoryAssigned / 1MB, 0)
                            MemoryDemand = [Math]::Round($vm.MemoryDemand / 1MB, 0)
                            Uptime = $vm.Uptime.ToString("d'd 'h'h 'm'm'")
                            Generation = $vm.Generation
                            Version = $vm.Version
                        }
                        
                        # Vérifier les checkpoints
                        $checkpoints = @(Get-VMCheckpoint -VMName $vm.Name -ErrorAction SilentlyContinue)
                        $vmDetail.Checkpoints = $checkpoints.Count
                        
                        # Vérifier la réplication
                        $replication = Get-VMReplication -VMName $vm.Name -ErrorAction SilentlyContinue
                        if ($replication) {
                            $vmDetail.ReplicationState = $replication.State
                            $vmDetail.ReplicationHealth = $replication.Health
                            $vmDetail.ReplicationServer = $replication.ReplicaServer
                        } else {
                            $vmDetail.ReplicationState = "None"
                        }
                        
                        $hyperVDetails += $vmDetail
                        
                    } catch {
                        Write-Host "Erreur analyse VM $($vm.Name): $_" -ForegroundColor Yellow
                    }
                }
                
                # Analyse réplication globale
                $replicas = @($hyperVDetails | Where-Object { $_.ReplicationState -ne "None" })
                if ($replicas.Count -gt 0) {
                    $healthyReplicas = @($replicas | Where-Object { $_.ReplicationHealth -eq "Normal" }).Count
                    $replicationStatus = "Active($healthyReplicas/$($replicas.Count))"
                } else {
                    $replicationStatus = "None"
                }
                
                Write-Host "Réplication: $replicationStatus" -ForegroundColor Green
                
            } else {
                $hyperVStatus = "OK(0VM)"
                Write-Host "Aucune VM trouvée" -ForegroundColor Yellow
            }
            
        } else {
            $hyperVStatus = "NotInstalled"
            Write-Host "Hyper-V non installé" -ForegroundColor Yellow
        }
        
    } catch {
        $hyperVStatus = "Error: $_"
        Write-Host "Erreur Hyper-V: $_" -ForegroundColor Red
    }
    
    # Uptime
    $uptime = ""
    try {
        $bootTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
        if ($bootTime) {
            $uptimeSpan = (Get-Date) - $bootTime
            $uptime = "$($uptimeSpan.Days)j $($uptimeSpan.Hours)h $($uptimeSpan.Minutes)m"
        }
    } catch { $uptime = "Error" }
    
    # Données pour ATLAS-Servers
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
        VeeamStatus = "$VERSION-HYPERV-DETAILED"
    }
    
    # Log principal dans ATLAS_LOGS
    $logMessage = "v0.17: CPU=$cpuUsage%, RAM=$memoryUsage%, Disk=$($diskSpaceGB)GB, Hyper-V: $hyperVStatus, Réplication: $replicationStatus"
    $logData = @{
        fields = @{
            Title = "Metrics-v0.17-$(Get-Date -Format 'HHmmss')"
            Hostname = $env:COMPUTERNAME
            Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            Level = "INFO"
            Source = "HyperVCollector"
            Message = $logMessage
            Details = "Uptime: $uptime | VMs: $($hyperVDetails.Count)"
        }
    }
    
    # Envoyer logs détaillés pour chaque VM
    $logsUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/bd8d22c0-a9dc-4116-9a29-a590b429826e/items"
    
    # Log principal
    try {
        Invoke-RestMethod -Uri $logsUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($logData | ConvertTo-Json -Depth 5) | Out-Null
    } catch {}
    
    # Log détaillé par VM
    foreach ($vmDetail in $hyperVDetails) {
        try {
            $vmLogData = @{
                fields = @{
                    Title = "VM-$($vmDetail.Name)-$(Get-Date -Format 'HHmmss')"
                    Hostname = $env:COMPUTERNAME
                    Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                    Level = "INFO"
                    Source = "VMDetail"
                    Message = "VM $($vmDetail.Name): $($vmDetail.State) | CPU: $($vmDetail.CPUUsage)% | RAM: $($vmDetail.MemoryAssigned)MB"
                    Details = "Checkpoints: $($vmDetail.Checkpoints) | Replication: $($vmDetail.ReplicationState) | Uptime: $($vmDetail.Uptime)"
                }
            }
            Invoke-RestMethod -Uri $logsUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($vmLogData | ConvertTo-Json -Depth 5) | Out-Null
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
        Write-Host "Métriques v0.17 Hyper-V mises à jour" -ForegroundColor Green
    } else {
        $createData = @{ fields = $data }
        Invoke-RestMethod -Uri $listUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($createData | ConvertTo-Json -Depth 5) | Out-Null
        Write-Host "Nouveau serveur v0.17 créé" -ForegroundColor Green
    }
    
} catch {
    Write-Host "Erreur: $_" -ForegroundColor Red
    
    # Log d'erreur
    try {
        $errorLogData = @{
            fields = @{
                Title = "ERROR-v0.17-$(Get-Date -Format 'HHmmss')"
                Hostname = $env:COMPUTERNAME
                Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                Level = "ERROR"
                Source = "Agent"
                Message = "Erreur agent v0.17: $_"
                Details = $_.ScriptStackTrace
            }
        }
        
        $logsUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/bd8d22c0-a9dc-4116-9a29-a590b429826e/items"
        $token = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$((Get-Content 'C:\ATLAS\config.json' | ConvertFrom-Json).TenantId)/oauth2/v2.0/token" -Body @{client_id=(Get-Content 'C:\ATLAS\config.json' | ConvertFrom-Json).ClientId;scope="https://graph.microsoft.com/.default";client_secret=(Get-Content 'C:\ATLAS\config.json' | ConvertFrom-Json).ClientSecret;grant_type="client_credentials"}).access_token
        
        Invoke-RestMethod -Uri $logsUrl -Headers @{"Authorization"="Bearer $token";"Content-Type"="application/json"} -Method POST -Body ($errorLogData | ConvertTo-Json -Depth 5) | Out-Null
    } catch {}
}

Write-Host "Agent $VERSION terminé." -ForegroundColor Green