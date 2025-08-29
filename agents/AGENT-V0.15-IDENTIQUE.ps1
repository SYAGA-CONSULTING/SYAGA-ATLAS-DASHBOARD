# ATLAS AGENT v0.15 - VRAI AUTO-UPDATE
# NOUVEAUTE v0.15: Identique v0.14 mais version 0.15 pour test auto-update
param([switch]$Install)

$VERSION = "v0.15"

if ($Install) {
    Write-Host "Installation Agent $VERSION..." -ForegroundColor Green
    Write-Host "Nouveaute: VRAI auto-update automatique" -ForegroundColor Cyan
    
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    schtasks.exe /Create /TN "ATLAS-Monitor" /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\temp\agent-latest.ps1" /SC MINUTE /MO 2 /RU SYSTEM /RL HIGHEST /F
    Start-ScheduledTask -TaskName "ATLAS-Monitor"
    
    Write-Host "Agent $VERSION avec VRAI auto-update installe" -ForegroundColor Green
    exit 0
}

# EXECUTION
Write-Host "Agent $VERSION execute..." -ForegroundColor Cyan

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
    
    # VRAI AUTO-UPDATE - Telecharger et verifier version
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
            Write-Host "Mise a jour $VERSION -> $latestVersion" -ForegroundColor Cyan
            
            # Sauvegarder et executer
            $latestAgent | Out-File "C:\temp\agent-latest.ps1" -Encoding UTF8 -Force
            Write-Host "Lancement installation nouvelle version..." -ForegroundColor Yellow
            & "C:\temp\agent-latest.ps1" -Install
            
            Write-Host "Auto-update termine! Nouvelle version installee." -ForegroundColor Green
            exit 0
        } else {
            Write-Host "Deja a jour ($VERSION)" -ForegroundColor Green
        }
    }
    
    # Hyper-V
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
    
    # Donnees
    $data = @{
        Title = $env:COMPUTERNAME
        Hostname = $env:COMPUTERNAME
        AgentVersion = $VERSION
        LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        State = "OK"
        HyperVStatus = $hyperVStatus
        CPUUsage = [double]5
        MemoryUsage = [double]50
        DiskSpaceGB = [double]342
        VeeamStatus = "$VERSION-AUTO-UPDATE-OK"
    }
    
    # Envoyer a SharePoint
    $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
    
    $existingUrl = "$listUrl`?`$expand=fields"
    $existing = Invoke-RestMethod -Uri $existingUrl -Headers $headers
    
    $myItem = $existing.value | Where-Object { $_.fields.Hostname -eq $env:COMPUTERNAME }
    
    if ($myItem) {
        # Mise a jour
        $updateUrl = "$listUrl/$($myItem.id)"
        $updateData = @{ fields = $data }
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PATCH -Body ($updateData | ConvertTo-Json -Depth 5) -ContentType "application/json"
        Write-Host "Donnees mises a jour dans SharePoint" -ForegroundColor Green
    } else {
        # Creation
        $createData = @{ fields = $data }
        Invoke-RestMethod -Uri $listUrl -Headers $headers -Method POST -Body ($createData | ConvertTo-Json -Depth 5) -ContentType "application/json"
        Write-Host "Nouveau serveur cree dans SharePoint" -ForegroundColor Green
    }
    
} catch {
    Write-Host "Erreur: $_" -ForegroundColor Red
}

Write-Host "Agent $VERSION termine." -ForegroundColor Green