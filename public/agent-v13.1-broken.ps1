# ATLAS Agent v13.1 - VERSION VOLONTAIREMENT CASSÉE POUR TEST ROLLBACK
$script:Version = "13.1-BROKEN"
$script:FoundationVersion = "10.3"
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
$commandsListId = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

# Buffer logs
$script:LogsBuffer = ""
$script:ErrorCount = 0

# ════════════════════════════════════════════════════
# FONCTION LOG
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    if ($Level -eq "ERROR") {
        $script:ErrorCount++
    }
    
    $script:LogsBuffer += "$logEntry`r`n"
    
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "ROLLBACK" { Write-Host $logEntry -ForegroundColor Magenta -BackgroundColor Yellow }
        default { Write-Host $logEntry }
    }
    
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════
# v13.1 BROKEN: GÉNÈRE VOLONTAIREMENT DES ERREURS
# ════════════════════════════════════════════════════
function Generate-Errors {
    Write-Log "v13.1 BROKEN - Generating intentional errors..." "WARNING"
    
    # Erreur 1: Division par zéro
    try {
        $result = 1 / 0
    } catch {
        Write-Log "ERROR 1: Division by zero - $_" "ERROR"
    }
    
    # Erreur 2: Fichier inexistant
    try {
        Get-Content "C:\FileDoesNotExist123456789.txt" -ErrorAction Stop
    } catch {
        Write-Log "ERROR 2: File not found - $_" "ERROR"
    }
    
    # Erreur 3: WMI invalide
    try {
        Get-WmiObject -Class "Win32_InvalidClass" -ErrorAction Stop
    } catch {
        Write-Log "ERROR 3: Invalid WMI class - $_" "ERROR"
    }
    
    # Erreur 4: SharePoint avec mauvais secret
    try {
        $badSecret = "INVALID_SECRET_12345"
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $badSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
    } catch {
        Write-Log "ERROR 4: SharePoint auth failed - $_" "ERROR"
    }
    
    # Erreur 5-10: Boucle d'erreurs
    for ($i = 5; $i -le 10; $i++) {
        Write-Log "ERROR $i: Simulated failure for rollback test" "ERROR"
    }
    
    Write-Log "Total errors generated: $($script:ErrorCount)" "WARNING"
}

# ════════════════════════════════════════════════════
# ROLLBACK AUTOMATIQUE SI TROP D'ERREURS
# ════════════════════════════════════════════════════
function Check-And-Rollback {
    Write-Log "Checking error count: $($script:ErrorCount)" "WARNING"
    
    if ($script:ErrorCount -gt 8) {
        Write-Log "════════════════════════════════════════" "ROLLBACK"
        Write-Log "!!! TOO MANY ERRORS - INITIATING ROLLBACK !!!" "ROLLBACK"
        Write-Log "!!! Errors: $($script:ErrorCount) > Threshold: 8 !!!" "ROLLBACK"
        Write-Log "════════════════════════════════════════" "ROLLBACK"
        
        try {
            # Télécharger v10.3
            $foundationUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v10.3.ps1"
            $agentPath = "C:\SYAGA-ATLAS\agent.ps1"
            
            Write-Log "Downloading foundation v10.3..." "ROLLBACK"
            Invoke-WebRequest -Uri $foundationUrl -OutFile $agentPath -UseBasicParsing -ErrorAction Stop
            
            if (Test-Path $agentPath) {
                Write-Log "Foundation v10.3 restored!" "SUCCESS"
                
                # Créer alerte dans SharePoint
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
                    
                    $alertCommand = @{
                        "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
                        Title = "ROLLBACK_v13.1_to_v10.3"
                        CommandType = "ROLLBACK_AUTO"
                        TargetVersion = "10.3"
                        TargetHostname = $hostname
                        Status = "ALERT"
                        CreatedBy = "v13.1-BROKEN"
                        ExecutedBy = "Auto-rollback after $($script:ErrorCount) errors"
                    }
                    
                    $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
                    Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body ($alertCommand | ConvertTo-Json)
                    
                    Write-Log "Rollback alert sent!" "SUCCESS"
                } catch {
                    Write-Log "Could not send alert: $_" "WARNING"
                }
                
                Write-Log "ROLLBACK COMPLETE - Restarting with v10.3" "SUCCESS"
                Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
                exit 0
            }
            
        } catch {
            Write-Log "ROLLBACK FAILED: $_" "ERROR"
        }
    }
}

# ════════════════════════════════════════════════════
# MAIN v13.1 BROKEN
# ════════════════════════════════════════════════════
Write-Log "════════════════════════════════════════" "WARNING"
Write-Log "Agent v13.1 - INTENTIONALLY BROKEN FOR TEST" "WARNING"
Write-Log "This version will generate errors and rollback" "WARNING"
Write-Log "════════════════════════════════════════" "WARNING"

# Générer des erreurs volontairement
Generate-Errors

# Vérifier si rollback nécessaire
Check-And-Rollback

# Si on arrive ici, pas assez d'erreurs (ne devrait pas arriver)
Write-Log "Not enough errors for rollback?" "WARNING"
Write-Log "Generating more errors..." "WARNING"

# Générer plus d'erreurs
for ($i = 1; $i -le 5; $i++) {
    Write-Log "CRITICAL ERROR $i: Force rollback" "ERROR"
}

# Re-vérifier
Check-And-Rollback

Write-Log "v13.1 BROKEN ended (should have rolled back!)" "ERROR"
exit 1