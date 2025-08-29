# AGENT SIMPLE QUI MARCHE - v6.0 qui supprime les anciennes taches

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Test
)

# Configuration - LECTURE DEPUIS FICHIER
$configPath = "C:\ATLAS\config.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $ClientId = $config.ClientId
    $TenantId = $config.TenantId
    $ClientSecret = $config.ClientSecret
} else {
    Write-Host "ERREUR: Fichier config manquant: $configPath" -ForegroundColor Red
    exit 1
}

$SiteId = "syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8"
$ListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] v5.8-SIMPLE $Message"
    $logPath = "C:\ATLAS\Logs\Agent-$(Get-Date -Format 'yyyyMMdd').log"
    
    if (-not (Test-Path "C:\ATLAS\Logs")) {
        New-Item -Path "C:\ATLAS\Logs" -ItemType Directory -Force | Out-Null
    }
    
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
    
    if ($Test -or $Level -eq "ERROR") {
        Write-Host $logEntry -ForegroundColor $(
            switch ($Level) {
                "ERROR" { "Red" }
                "SUCCESS" { "Green" }
                "WARNING" { "Yellow" }
                default { "White" }
            }
        )
    }
}

function Get-AccessToken {
    Write-Log "Getting access token from Azure AD"
    $body = @{
        client_id = $ClientId
        scope = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type = "client_credentials"
    }
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    try {
        $response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType "application/x-www-form-urlencoded"
        Write-Log "Access token obtained successfully" "SUCCESS"
        return $response.access_token
    } catch {
        Write-Log "Failed to get access token: $_" "ERROR"
        return $null
    }
}

function Get-SystemMetrics {
    try {
        # CPU Usage
        $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
        $cpuUsage = if($cpu.LoadPercentage) { [double]$cpu.LoadPercentage } else { [double]5 }
        
        # Memory Usage
        $mem = Get-WmiObject Win32_OperatingSystem
        $memUsage = [double]([math]::Round((($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory) / $mem.TotalVisibleMemorySize * 100), 2))
        
        # Disk Space
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [double]([math]::Round($disk.FreeSpace / 1GB, 2))
        
        # IP Address
        $ipAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        if (!$ipAddress) { $ipAddress = "0.0.0.0" }
        
        # Build metrics object with correct field names
        return @{
            Title = [string]$env:COMPUTERNAME
            Hostname = [string]$env:COMPUTERNAME
            State = "OK"
            IPAddress = [string]$ipAddress
            Role = "Server"
            CPUUsage = $cpuUsage
            MemoryUsage = $memUsage
            DiskSpaceGB = $diskFreeGB
            HyperVStatus = "N/A"
            VeeamStatus = "N/A"
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = "5.8-SIMPLE"
            PendingUpdates = [double]0
        }
    } catch {
        Write-Log "Failed to collect metrics: $_" "ERROR"
        return $null
    }
}

function Send-ToSharePoint {
    param($Metrics, $Token)
    
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type" = "application/json"
        "Accept" = "application/json"
    }
    
    try {
        # Get all items
        $itemsUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items?`$expand=fields"
        $allItems = Invoke-RestMethod -Uri $itemsUrl -Headers $headers -Method GET
        
        # Find our server manually
        $existingItem = $null
        foreach ($item in $allItems.value) {
            if ($item.fields.Hostname -eq $env:COMPUTERNAME -or $item.fields.Title -eq $env:COMPUTERNAME) {
                    $existingItem = $item
                break
            }
        }
        
        $body = @{ fields = $Metrics } | ConvertTo-Json -Depth 10
        
        if ($existingItem) {
            # Update existing item
            $itemId = $existingItem.id
            $updateUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items/$itemId"
            $response = Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PATCH -Body $body
            Write-Log "Updated SharePoint item $itemId successfully" "SUCCESS"
        } else {
            # Create new item
            $createUrl = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items"
            $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $body
            Write-Log "Created new SharePoint item successfully" "SUCCESS"
        }
        return $true
    } catch {
        Write-Log "Failed to send to SharePoint: $_" "ERROR"
        return $false
    }
}

function Install-Agent {
    Write-Host "Installing ATLAS Agent v6.0 FINAL" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # SUPPRIMER TOUTES LES ANCIENNES TACHES ATLAS
    Write-Host "Suppression anciennes taches ATLAS..." -ForegroundColor Yellow
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Write-Host "Supprime: $($_.TaskName)" -ForegroundColor Red
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    Write-Host "Anciennes taches supprimees" -ForegroundColor Green
    
    # Check Administrator rights
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERROR: Must run as Administrator" -ForegroundColor Red
        exit 1
    }
    
    # Copy script to target location
    $targetPath = "C:\ATLAS\Agent\ATLAS-Agent-Current.ps1"
    if ($PSCommandPath -and $PSCommandPath -ne $targetPath) {
        Write-Host "Copying script to $targetPath..."
        if (-not (Test-Path "C:\ATLAS\Agent")) {
            New-Item -Path "C:\ATLAS\Agent" -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $PSCommandPath -Destination $targetPath -Force
    }
    
    # Remove old tasks
    Write-Host "Removing old tasks..."
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
        Write-Host "  Removed: $($_.TaskName)" -ForegroundColor Yellow
    }
    
    # Create scheduled task using schtasks.exe
    Write-Host "Creating scheduled task..."
    
    $taskName = "ATLAS-Agent-v5"
    
    $result = schtasks.exe /Create `
        /TN $taskName `
        /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -File `"$targetPath`"" `
        /SC MINUTE `
        /MO 3 `
        /RU SYSTEM `
        /RL HIGHEST `
        /F 2>&1
    
    Write-Host "Result: $result"
    
    # Verify and start
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "Task created successfully!" -ForegroundColor Green
        
        # Run once immediately
        Write-Host "Starting initial execution..."
        Start-ScheduledTask -TaskName $taskName
        
        Start-Sleep -Seconds 3
        
        Write-Host ""
        Write-Host "Installation Complete!" -ForegroundColor Green
        Write-Host "Version: 5.8-SIMPLE" -ForegroundColor Green
        Write-Host "Dashboard: https://white-river-053fc6703.2.azurestaticapps.net" -ForegroundColor Cyan
    } else {
        Write-Host "ERROR: Task creation failed!" -ForegroundColor Red
        exit 1
    }
}

function Uninstall-Agent {
    Write-Host "Uninstalling ATLAS Agent..." -ForegroundColor Yellow
    
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Write-Host "Removing: $($_.TaskName)"
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
    }
    
    Write-Host "Uninstall complete" -ForegroundColor Green
}

function Test-Agent {
    Write-Host "Test Mode - Running once" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    $token = Get-AccessToken
    if ($token) {
        Write-Host "Token: OK" -ForegroundColor Green
        
        $metrics = Get-SystemMetrics
        Write-Host ""
        Write-Host "Metrics collected:" -ForegroundColor Yellow
        $metrics | Format-Table
        
        Write-Host "Sending to SharePoint..."
        $result = Send-ToSharePoint -Metrics $metrics -Token $token
        
        if ($result) {
            Write-Host "SUCCESS - Data sent to SharePoint!" -ForegroundColor Green
        } else {
            Write-Host "FAILED - Check logs" -ForegroundColor Red
        }
    } else {
        Write-Host "FAILED - Could not get access token" -ForegroundColor Red
    }
}

# Main execution
if ($Install) {
    Install-Agent
} elseif ($Uninstall) {
    Uninstall-Agent
} elseif ($Test) {
    Test-Agent
} else {
    # Normal execution - run once and exit
    Write-Log "Agent execution started"
    
    $token = Get-AccessToken
    if ($token) {
        $metrics = Get-SystemMetrics
        if ($metrics) {
            $result = Send-ToSharePoint -Metrics $metrics -Token $token
            if (-not $result) {
                exit 1
            }
        } else {
            Write-Log "Failed to collect metrics" "ERROR"
            exit 1
        }
    } else {
        exit 1
    }
    
    Write-Log "Agent execution completed successfully"
}