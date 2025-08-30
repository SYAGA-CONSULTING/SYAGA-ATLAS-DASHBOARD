# ATLAS AGENT v0.21 - ULTRA SIMPLE
param([switch]$Install)

$VERSION = "v0.21"

if ($Install) {
    Write-Host "Installation Agent $VERSION..." -ForegroundColor Green
    if (!(Test-Path "C:\SYAGA-ATLAS")) {
        New-Item -Path "C:\SYAGA-ATLAS" -ItemType Directory -Force | Out-Null
    }
    Copy-Item $PSCommandPath "C:\SYAGA-ATLAS\agent.ps1" -Force
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    schtasks.exe /Create /TN "SYAGA-ATLAS-Agent" /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\SYAGA-ATLAS\agent.ps1" /SC MINUTE /MO 2 /RU SYSTEM /RL HIGHEST /F
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent"
    Write-Host "Agent $VERSION installe" -ForegroundColor Green
    exit 0
}

# EXECUTION
$H = $env:COMPUTERNAME
Write-Host "[$H] $VERSION running..." -ForegroundColor Cyan

try {
    # Token
    $tokenBody = @{
        client_id = 'f66a8c6c-1037-41b8-be3c-4f6e67c1f49e'
        client_secret = '[REDACTED]'
        scope = 'https://graph.microsoft.com/.default'
        grant_type = 'client_credentials'
    }
    $token = (Invoke-RestMethod -Uri 'https://login.microsoftonline.com/6027d81c-ad9b-48f5-9da6-96f1bad11429/oauth2/v2.0/token' -Method Post -Body $tokenBody).access_token
    
    # Metriques
    $cpu = 5
    try {
        $c = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        if ($c) { $cpu = [Math]::Round($c.CounterSamples[0].CookedValue, 1) }
    }
    catch {
        try {
            $c = Get-Counter "\Processeur(_Total)\% temps processeur" -ErrorAction SilentlyContinue
            if ($c) { $cpu = [Math]::Round($c.CounterSamples[0].CookedValue, 1) }
        }
        catch {}
    }
    
    $mem = 50
    try {
        $os = Get-WmiObject Win32_OperatingSystem
        $mem = [Math]::Round(100 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100), 1)
    }
    catch {}
    
    $disk = 100
    try {
        $d = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object -First 1
        $disk = [Math]::Round($d.FreeSpace / 1GB, 1)
    }
    catch {}
    
    # Data
    $data = @{
        Hostname = $H
        Title = $H
        AgentVersion = $VERSION
        LastContact = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        State = 'OK'
        CPUUsage = $cpu
        MemoryUsage = $mem
        DiskSpaceGB = $disk
    }
    
    # SharePoint
    $headers = @{Authorization = "Bearer $token"}
    $listUrl = 'https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?$expand=fields'
    $items = Invoke-RestMethod -Uri $listUrl -Headers $headers
    
    $myItem = $items.value | Where-Object { $_.fields.Hostname -eq $H } | Select-Object -First 1
    
    if ($myItem) {
        # Update
        $updateUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items/$($myItem.id)"
        $body = @{fields = $data} | ConvertTo-Json
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PATCH -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
        Write-Host "[$H] $VERSION updated - CPU:$cpu% RAM:$mem% Disk:$disk GB" -ForegroundColor Green
    }
    else {
        # Create
        try {
            $body = @{fields = $data} | ConvertTo-Json
            Invoke-RestMethod -Uri $listUrl.Split('?')[0] -Headers $headers -Method POST -Body $body -ContentType 'application/json; charset=utf-8' | Out-Null
            Write-Host "[$H] $VERSION created" -ForegroundColor Green
        }
        catch {
            Write-Host "[$H] Entry exists" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "[$H] Error: $_" -ForegroundColor Red
}