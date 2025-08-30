# SYAGA ATLAS AGENT v0.19 - VERSION UNIFIÉE
# Pour SYAGA-HOST01 et SYAGA-VEEAM01
# Secret permanent + Toutes métriques

param(
    [string]$Hostname = $env:COMPUTERNAME
)

$VERSION = "v0.19"

# Collecter métriques avancées
# CPU avec gestion erreur pour langue FR
$cpu = try { 
    $counter = Get-Counter "\Processeur(_Total)\% temps processeur" -ErrorAction SilentlyContinue
    if (!$counter) {
        $counter = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
    }
    [Math]::Round($counter.CounterSamples[0].CookedValue, 1)
} catch { 0 }

# RAM
$mem = Get-WmiObject Win32_OperatingSystem
$memUsage = [Math]::Round((($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory) / $mem.TotalVisibleMemorySize) * 100, 1)

# Disk
$disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskFree = [Math]::Round($disk.FreeSpace / 1GB, 1)
$diskTotal = [Math]::Round($disk.Size / 1GB, 1)
$diskUsed = [Math]::Round(($diskTotal - $diskFree), 1)

# Veeam détaillé
$veeamServices = Get-Service -Name "Veeam*" -ErrorAction SilentlyContinue
if ($veeamServices) {
    $runningVeeam = ($veeamServices | Where-Object {$_.Status -eq "Running"}).Count
    $totalVeeam = $veeamServices.Count
    $veeamStatus = "Installed($runningVeeam/$totalVeeam)"
    
    # Essayer de récupérer jobs Veeam
    try {
        Add-PSSnapin VeeamPSSnapin -ErrorAction SilentlyContinue
        $jobs = Get-VBRJob -ErrorAction SilentlyContinue
        if ($jobs) {
            $veeamStatus = "Jobs:" + $jobs.Count
        }
    } catch {
        # Pas d'accès aux jobs
    }
} else {
    $veeamStatus = "NotInstalled"
}

# IP et réseau
$networkInfo = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | Select-Object -First 1
$ipAddress = if ($networkInfo) { $networkInfo.IPAddress } else { "Unknown" }

# Hyper-V si HOST01
$hyperVStatus = "N/A"
if ($Hostname -eq "SYAGA-HOST01") {
    try {
        $vms = Get-VM -ErrorAction SilentlyContinue
        if ($vms) {
            $running = ($vms | Where-Object {$_.State -eq "Running"}).Count
            $total = $vms.Count
            $hyperVStatus = "OK($running/$total)"
        }
    } catch {
        $hyperVStatus = "NoAccess"
    }
} else {
    # Pour VEEAM01, mettre l'IP dans HyperVStatus
    $hyperVStatus = $ipAddress
}

# Windows Update
$updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction SilentlyContinue
$updateStatus = "Unknown"
if ($updateSession) {
    try {
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0")
        $updateStatus = "Pending:" + $searchResult.Updates.Count
    } catch {
        $updateStatus = "NoAccess"
    }
}

# Obtenir token Azure AD
$tokenUrl = "https://login.microsoftonline.com/6027d81c-ad9b-48f5-9da6-96f1bad11429/oauth2/v2.0/token"
$tokenBody = @{
    client_id = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
    client_secret = "[REDACTED]"
    scope = "https://graph.microsoft.com/.default"
    grant_type = "client_credentials"
}

try {
    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody
    $accessToken = $tokenResponse.access_token
    
    # Préparer métriques complètes
    $metrics = @{
        Hostname = $Hostname
        Title = $Hostname
        AgentVersion = $VERSION
        LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss") + "Z"
        State = "OK"
        CPUUsage = $cpu
        MemoryUsage = $memUsage
        DiskSpaceGB = $diskFree
        VeeamStatus = $veeamStatus
        HyperVStatus = $hyperVStatus
    }
    
    # Envoyer à SharePoint
    $headers = @{ 
        Authorization = "Bearer $accessToken"
        "Content-Type" = "application/json; charset=utf-8"
    }
    
    $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
    
    # Chercher item existant
    $existing = Invoke-RestMethod -Uri "$listUrl`?`$expand=fields" -Headers $headers -Method Get
    $item = $existing.value | Where-Object { $_.fields.Hostname -eq $Hostname }
    
    $body = @{ fields = $metrics } | ConvertTo-Json -Depth 10
    
    if ($item) {
        # Update
        Invoke-RestMethod -Uri "$listUrl/$($item.id)" -Headers $headers -Method PATCH -Body $body -ContentType "application/json; charset=utf-8" | Out-Null
        Write-Host "[$Hostname] v0.19 Updated - CPU:$cpu% RAM:$memUsage% Disk:$diskFree/$diskTotal GB Veeam:$veeamStatus"
    } else {
        # Create
        Invoke-RestMethod -Uri $listUrl -Headers $headers -Method POST -Body $body -ContentType "application/json; charset=utf-8" | Out-Null
        Write-Host "[$Hostname] v0.19 Created - CPU:$cpu% RAM:$memUsage% Disk:$diskFree/$diskTotal GB Veeam:$veeamStatus"
    }
    
} catch {
    Write-Host "Error: $_"
}