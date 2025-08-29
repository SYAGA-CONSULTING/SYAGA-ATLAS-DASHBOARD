# ATLAS AGENT v0.20 - AVEC INSTALLATION
param([switch]$Install)

$VERSION = "v0.20"

if ($Install) {
    Write-Host "Installation ATLAS Agent $VERSION..." -ForegroundColor Green
    
    # Créer dossier
    if (!(Test-Path "C:\SYAGA-ATLAS")) {
        New-Item -Path "C:\SYAGA-ATLAS" -ItemType Directory -Force | Out-Null
    }
    
    # Copier agent
    Copy-Item $PSCommandPath "C:\SYAGA-ATLAS\agent.ps1" -Force
    
    # Supprimer anciennes tâches
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    # Créer nouvelle tâche
    schtasks.exe /Create /TN "SYAGA-ATLAS-Agent" /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\SYAGA-ATLAS\agent.ps1" /SC MINUTE /MO 2 /RU SYSTEM /RL HIGHEST /F
    
    # Démarrer
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent"
    
    Write-Host "Agent $VERSION installé dans C:\SYAGA-ATLAS" -ForegroundColor Green
    Write-Host "Tâche planifiée SYAGA-ATLAS-Agent créée" -ForegroundColor Green
    exit 0
}

# EXECUTION NORMALE
$H=$env:COMPUTERNAME
Write-Host "[$H] Agent $VERSION running..." -ForegroundColor Cyan

try{
$t=Invoke-RestMethod -Uri "https://login.microsoftonline.com/6027d81c-ad9b-48f5-9da6-96f1bad11429/oauth2/v2.0/token" -Method Post -Body @{client_id="f66a8c6c-1037-41b8-be3c-4f6e67c1f49e";client_secret="[REDACTED]";scope="https://graph.microsoft.com/.default";grant_type="client_credentials"}
$h=@{Authorization="Bearer $($t.access_token)"}

# CPU avec gestion FR/EN
$cpu=5
try{$c=Get-Counter "\Processor(_Total)\% Processor Time" -EA SilentlyContinue;if($c){$cpu=[Math]::Round($c.CounterSamples[0].CookedValue,1)}}catch{}
if($cpu -eq 5){try{$c=Get-Counter "\Processeur(_Total)\% temps processeur" -EA SilentlyContinue;if($c){$cpu=[Math]::Round($c.CounterSamples[0].CookedValue,1)}}catch{}}

# RAM
$mem=50
try{$os=Get-WmiObject Win32_OperatingSystem;$mem=[Math]::Round(100-($os.FreePhysicalMemory/$os.TotalVisibleMemorySize*100),1)}catch{}

# Disk
$disk=100
try{$d=Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"|Select -First 1;$disk=[Math]::Round($d.FreeSpace/1GB,1)}catch{}

$m=@{
    Hostname=$H
    Title=$H
    AgentVersion=$VERSION
    LastContact=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    State="OK"
    CPUUsage=$cpu
    MemoryUsage=$mem
    DiskSpaceGB=$disk
}

$u="https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
$e=Invoke-RestMethod -Uri "$u`?`$expand=fields&`$filter=fields/Hostname eq '$H'" -Headers $h

if($e.value.Count -gt 0){
    $id=$e.value[0].id
    Invoke-RestMethod -Uri "$u/$id" -Headers $h -Method PATCH -Body (@{fields=$m}|ConvertTo-Json) -ContentType "application/json"|Out-Null
    Write-Host "[$H] $VERSION updated - CPU:$cpu% RAM:$mem% Disk:$disk GB" -ForegroundColor Green
}else{
    Write-Host "[$H] $VERSION - Creating entry..." -ForegroundColor Yellow
    try{
        Invoke-RestMethod -Uri $u -Headers $h -Method POST -Body (@{fields=$m}|ConvertTo-Json) -ContentType "application/json"|Out-Null
        Write-Host "[$H] $VERSION created" -ForegroundColor Green
    }catch{
        Write-Host "[$H] $VERSION - Entry exists, will update next cycle" -ForegroundColor Cyan
    }
}

# AUTO-UPDATE CHECK
Write-Host "Checking for updates..." -ForegroundColor Gray
$updateUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/drive/root:/ATLAS/atlas-agent-current.ps1:/content"
try{
    $latest = Invoke-RestMethod -Uri $updateUrl -Headers $h -Method GET
    if($latest -match 'VERSION = "v([\d\.]+)"'){
        $latestVer = $Matches[1]
        if($latestVer -ne "0.20"){
            Write-Host "New version available: v$latestVer" -ForegroundColor Cyan
            $latest | Out-File "C:\SYAGA-ATLAS\agent.ps1" -Encoding UTF8 -Force
            Write-Host "Updated to v$latestVer - Will restart next cycle" -ForegroundColor Green
        }
    }
}catch{Write-Host "Update check failed" -ForegroundColor Gray}

}catch{Write-Host "[$H] $VERSION Error: $_" -ForegroundColor Red}