# ATLAS Agent v10.3 - AVEC MODULE VALIDATION AUTONOME
# Mode: TEST VALIDATION FONDATION
# Date: 4 septembre 2025

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$TestValidation
)

$ErrorActionPreference = "Stop"
$script:Version = "v10.3-validation"
$script:BaseDir = "C:\SYAGA-ATLAS"
$script:LogFile = "$BaseDir\logs\agent-$(Get-Date -Format 'yyyyMMdd').log"

# Configuration SharePoint
$script:Config = @{
    ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
    TenantId = "ee90ce10-784b-496e-8c0f-4fd959ff6bce"
    SharePointSite = "https://syagaconsulting.sharepoint.com/sites/SYAGA-ATLAS"
    Lists = @{
        Servers = "ATLAS-Servers"
        Commands = "ATLAS-Commands"
        Audit = "ATLAS-Audit"
        ValidationResults = "ATLAS-ValidationResults"  # Nouvelle liste pour résultats
    }
}

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    
    Add-Content -Path $script:LogFile -Value $logMessage -Encoding UTF8
    
    switch($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
}

function Test-V10Validation {
    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"
    Write-Log "DÉBUT VALIDATION AUTONOME v10.3" "SUCCESS"
    
    $results = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Hostname = $env:COMPUTERNAME
        Version = "v10.3"
        Status = "TESTING"
        Tests = @{}
        CanContinue = $true
    }
    
    try {
        # Test 1: Fichiers agent
        Write-Log "[TEST 1] Vérification fichiers agent..." "INFO"
        if (Test-Path "$BaseDir\agent.ps1") {
            $results.Tests["AgentFile"] = "PASS"
            Write-Log "✓ Agent présent" "SUCCESS"
        } else {
            $results.Tests["AgentFile"] = "FAIL"
            $results.CanContinue = $false
            Write-Log "✗ Agent manquant!" "ERROR"
        }
        
        # Test 2: Tâches planifiées
        Write-Log "[TEST 2] Vérification tâches planifiées..." "INFO"
        $tasks = @("SYAGA-ATLAS-Agent", "SYAGA-ATLAS-Updater")
        $allTasksOK = $true
        
        foreach ($taskName in $tasks) {
            try {
                $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                if ($task.State -eq "Ready") {
                    Write-Log "✓ Tâche $taskName: OK" "SUCCESS"
                } else {
                    Write-Log "⚠ Tâche $taskName: État $($task.State)" "WARNING"
                    $allTasksOK = $false
                }
            } catch {
                Write-Log "✗ Tâche $taskName: INTROUVABLE" "ERROR"
                $allTasksOK = $false
                $results.CanContinue = $false
            }
        }
        $results.Tests["ScheduledTasks"] = if ($allTasksOK) { "PASS" } else { "FAIL" }
        
        # Test 3: Connectivité SharePoint
        Write-Log "[TEST 3] Test connectivité SharePoint..." "INFO"
        try {
            $token = Get-SharePointToken
            if ($token) {
                $results.Tests["SharePointAuth"] = "PASS"
                Write-Log "✓ Authentification SharePoint OK" "SUCCESS"
            } else {
                $results.Tests["SharePointAuth"] = "FAIL"
                $results.CanContinue = $false
                Write-Log "✗ Échec authentification" "ERROR"
            }
        } catch {
            $results.Tests["SharePointAuth"] = "FAIL"
            $results.CanContinue = $false
            Write-Log "✗ Erreur SharePoint: $_" "ERROR"
        }
        
        # Test 4: Performance système
        Write-Log "[TEST 4] Analyse performance..." "INFO"
        $cpu = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        $memory = Get-WmiObject Win32_OperatingSystem
        $memUsage = [Math]::Round(($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) / $memory.TotalVisibleMemorySize * 100, 2)
        
        $results.Tests["Performance"] = @{
            CPU = $cpu
            Memory = $memUsage
            Status = if ($cpu -lt 80 -and $memUsage -lt 90) { "PASS" } else { "WARNING" }
        }
        
        Write-Log "CPU: $cpu% | RAM: $memUsage%" "INFO"
        
        # Test 5: Backup v10.3
        Write-Log "[TEST 5] Vérification backup..." "INFO"
        $backupPath = "C:\SYAGA-BACKUP-v10.3"
        
        if (-not (Test-Path $backupPath)) {
            Write-Log "Création backup fondation..." "INFO"
            try {
                Copy-Item -Path $BaseDir -Destination $backupPath -Recurse -Force
                $results.Tests["Backup"] = "CREATED"
                Write-Log "✓ Backup créé" "SUCCESS"
            } catch {
                $results.Tests["Backup"] = "FAIL"
                Write-Log "✗ Échec backup: $_" "ERROR"
            }
        } else {
            $results.Tests["Backup"] = "EXISTS"
            Write-Log "✓ Backup déjà présent" "SUCCESS"
        }
        
        # Déterminer statut global
        $failCount = ($results.Tests.Values | Where-Object { $_ -eq "FAIL" }).Count
        
        if ($failCount -eq 0) {
            $results.Status = "READY_FOR_EVOLUTION"
            Write-Log "✅ VALIDATION RÉUSSIE - PRÊT POUR ÉVOLUTION" "SUCCESS"
        } elseif ($results.CanContinue) {
            $results.Status = "PARTIAL_SUCCESS"
            Write-Log "⚠ VALIDATION PARTIELLE - Corrections mineures requises" "WARNING"
        } else {
            $results.Status = "ROLLBACK_REQUIRED"
            Write-Log "🔴 ÉCHEC VALIDATION - ROLLBACK NÉCESSAIRE" "ERROR"
        }
        
    } catch {
        $results.Status = "ERROR"
        $results.Error = $_.Exception.Message
        Write-Log "ERREUR CRITIQUE: $_" "ERROR"
    }
    
    # Envoyer résultats à SharePoint
    Send-ValidationResults $results
    
    # Si échec critique, initier rollback
    if ($results.Status -eq "ROLLBACK_REQUIRED") {
        Write-Log "INITIALISATION ROLLBACK AUTOMATIQUE..." "WARNING"
        Invoke-Rollback
    }
    
    return $results
}

function Get-SharePointToken {
    $certPath = "$BaseDir\atlas-cert.pfx"
    if (-not (Test-Path $certPath)) {
        throw "Certificat non trouvé"
    }
    
    $cert = Get-PfxCertificate -FilePath $certPath
    
    $body = @{
        client_id = $Config.ClientId
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        client_assertion = New-JwtToken -Certificate $cert
        scope = "https://graph.microsoft.com/.default"
        grant_type = "client_credentials"
    }
    
    $response = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($Config.TenantId)/oauth2/v2.0/token" `
        -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    
    return $response.access_token
}

function Send-ValidationResults($results) {
    try {
        $token = Get-SharePointToken
        
        $body = @{
            fields = @{
                Title = "$($env:COMPUTERNAME)-$(Get-Date -Format 'yyyyMMddHHmmss')"
                Hostname = $env:COMPUTERNAME
                ValidationTime = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
                Version = $results.Version
                Status = $results.Status
                TestResults = $results.Tests | ConvertTo-Json -Compress
                CanContinue = $results.CanContinue
            }
        } | ConvertTo-Json -Depth 10
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json;charset=utf-8"
        }
        
        $uri = "$($Config.SharePointSite)/_api/web/lists/getbytitle('$($Config.Lists.ValidationResults)')/items"
        
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        Write-Log "✓ Résultats envoyés à SharePoint" "SUCCESS"
        
    } catch {
        Write-Log "Erreur envoi résultats: $_" "ERROR"
    }
}

function Invoke-Rollback {
    Write-Log "═══════════════════════════════════════════════════════════════" "WARNING"
    Write-Log "ROLLBACK AUTOMATIQUE EN COURS" "WARNING"
    
    try {
        $backupPath = "C:\SYAGA-BACKUP-v10.3"
        
        if (Test-Path $backupPath) {
            Write-Log "Restauration depuis backup..." "INFO"
            
            # Arrêter les tâches
            Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
            Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
            
            # Restaurer fichiers
            Copy-Item -Path "$backupPath\*" -Destination $BaseDir -Recurse -Force
            
            # Redémarrer tâches
            Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
            Start-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
            
            Write-Log "✅ ROLLBACK TERMINÉ - v10.3 restaurée" "SUCCESS"
            
            # Notifier SharePoint
            Send-RollbackNotification "SUCCESS"
            
        } else {
            Write-Log "✗ Backup introuvable pour rollback!" "ERROR"
            Send-RollbackNotification "FAIL_NO_BACKUP"
        }
        
    } catch {
        Write-Log "✗ Échec rollback: $_" "ERROR"
        Send-RollbackNotification "FAIL_ERROR"
    }
}

function Send-RollbackNotification($status) {
    try {
        $token = Get-SharePointToken
        
        $body = @{
            fields = @{
                Title = "ROLLBACK-$($env:COMPUTERNAME)-$(Get-Date -Format 'yyyyMMddHHmmss')"
                Hostname = $env:COMPUTERNAME
                Action = "ROLLBACK_TO_V10.3"
                Status = $status
                Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
            }
        } | ConvertTo-Json
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json;charset=utf-8"
        }
        
        $uri = "$($Config.SharePointSite)/_api/web/lists/getbytitle('$($Config.Lists.Audit)')/items"
        
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
        
    } catch {
        Write-Log "Erreur notification rollback: $_" "ERROR"
    }
}

# Point d'entrée principal
if ($TestValidation) {
    Write-Log "Mode: TEST VALIDATION v10.3" "INFO"
    $results = Test-V10Validation
    
    # Afficher résumé
    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"
    Write-Log "RÉSUMÉ VALIDATION:" "INFO"
    Write-Log "Status: $($results.Status)" $(if ($results.Status -eq "READY_FOR_EVOLUTION") { "SUCCESS" } else { "WARNING" })
    Write-Log "Peut continuer: $($results.CanContinue)" "INFO"
    Write-Log "═══════════════════════════════════════════════════════════════" "INFO"
    
} elseif ($Install) {
    Write-Log "Installation agent v10.3-validation..." "INFO"
    # Code installation standard
    
} else {
    # Exécution normale agent
    Write-Log "Exécution agent v10.3 standard" "INFO"
    # Code agent normal
}

Write-Log "Fin exécution agent v10.3-validation" "INFO"