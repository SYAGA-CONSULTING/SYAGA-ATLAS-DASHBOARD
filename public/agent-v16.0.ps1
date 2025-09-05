# ════════════════════════════════════════════════════════════════════
# ATLAS Agent v16.0 - ROLLBACK AUTOMATIQUE INTELLIGENT  
# ════════════════════════════════════════════════════════════════════
# - Système de rollback multi-niveaux
# - Snapshots automatiques avant changements
# - Validation post-déploiement
# - Restauration automatique si échec
# ════════════════════════════════════════════════════════════════════

$script:Version = "16.0"
$script:SafeVersion = "13.6"  # Version stable de fallback
$hostname = $env:COMPUTERNAME
$atlasPath = "C:\SYAGA-ATLAS"

# Configuration SharePoint
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

# Buffer logs et historique
$script:LogsBuffer = ""
$script:MaxBufferSize = 10000
$script:DeploymentHistory = @()
$script:ValidationResults = @()

# ════════════════════════════════════════════════════════════════════
# SYSTÈME DE ROLLBACK v16.0
# ════════════════════════════════════════════════════════════════════
$script:RollbackConfig = @{
    MaxBackups = 5
    BackupPath = "$atlasPath\rollback"
    StateFile = "$atlasPath\deployment-state.json"
    ValidationTimeout = 300  # 5 minutes
}

$script:DeploymentState = @{
    CurrentVersion = $script:Version
    LastStableVersion = $script:SafeVersion
    DeploymentTime = $null
    ValidationStatus = "PENDING"
    RollbackCount = 0
    FailureHistory = @()
}

# ════════════════════════════════════════════════════════════════════
# SNAPSHOT ET BACKUP
# ════════════════════════════════════════════════════════════════════
function Create-Snapshot {
    param($Description = "Auto-snapshot")
    
    Write-Log "📸 Création snapshot: $Description" "INFO"
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $snapshotPath = "$($script:RollbackConfig.BackupPath)\snapshot-$timestamp"
    
    try {
        # Créer dossier backup si nécessaire
        if (!(Test-Path $script:RollbackConfig.BackupPath)) {
            New-Item -ItemType Directory -Path $script:RollbackConfig.BackupPath -Force | Out-Null
        }
        
        # Créer snapshot
        New-Item -ItemType Directory -Path $snapshotPath -Force | Out-Null
        
        # Sauvegarder état système
        $systemState = @{
            Version = $script:Version
            Timestamp = $timestamp
            Description = $Description
            Services = Get-ServiceStates
            Processes = Get-ProcessSnapshot
            Registry = Get-RegistrySnapshot
            Files = @()
        }
        
        # Sauvegarder fichiers ATLAS
        $filesToBackup = @(
            "$atlasPath\agent.ps1",
            "$atlasPath\updater.ps1",
            "$atlasPath\config.json"
        )
        
        foreach ($file in $filesToBackup) {
            if (Test-Path $file) {
                $fileName = Split-Path $file -Leaf
                Copy-Item $file "$snapshotPath\$fileName" -Force
                $systemState.Files += $fileName
            }
        }
        
        # Sauvegarder configuration IIS si présent
        if (Get-Service W3SVC -ErrorAction SilentlyContinue) {
            & appcmd add backup "$timestamp-atlas" 2>&1 | Out-Null
            $systemState.IISBackup = "$timestamp-atlas"
        }
        
        # Sauvegarder état en JSON
        $systemState | ConvertTo-Json -Depth 10 | 
            Set-Content "$snapshotPath\state.json" -Encoding UTF8
        
        # Nettoyer anciens backups
        Clean-OldSnapshots
        
        Write-Log "✅ Snapshot créé: $snapshotPath" "SUCCESS"
        return $snapshotPath
        
    } catch {
        Write-Log "❌ Échec création snapshot: $_" "ERROR"
        return $null
    }
}

function Restore-Snapshot {
    param($SnapshotPath)
    
    Write-Log "🔄 Restauration snapshot: $SnapshotPath" "WARNING"
    
    try {
        if (!(Test-Path "$SnapshotPath\state.json")) {
            throw "Snapshot invalide: state.json manquant"
        }
        
        $state = Get-Content "$SnapshotPath\state.json" -Raw | ConvertFrom-Json
        
        # Restaurer fichiers
        foreach ($file in $state.Files) {
            $source = "$SnapshotPath\$file"
            $dest = "$atlasPath\$file"
            
            if (Test-Path $source) {
                Copy-Item $source $dest -Force
                Write-Log "  ✓ Restauré: $file" "SUCCESS"
            }
        }
        
        # Restaurer IIS si nécessaire
        if ($state.IISBackup) {
            & appcmd restore backup $state.IISBackup 2>&1 | Out-Null
            Write-Log "  ✓ IIS restauré" "SUCCESS"
        }
        
        # Redémarrer services critiques
        Restore-Services $state.Services
        
        # Mettre à jour état
        $script:DeploymentState.CurrentVersion = $state.Version
        $script:DeploymentState.RollbackCount++
        Save-DeploymentState
        
        Write-Log "✅ Rollback complété vers v$($state.Version)" "SUCCESS"
        return $true
        
    } catch {
        Write-Log "❌ Échec rollback: $_" "ERROR"
        return $false
    }
}

# ════════════════════════════════════════════════════════════════════
# VALIDATION POST-DÉPLOIEMENT
# ════════════════════════════════════════════════════════════════════
function Validate-Deployment {
    Write-Log "🔍 Validation déploiement v$($script:Version)..." "INFO"
    
    $validation = @{
        Timestamp = Get-Date
        Version = $script:Version
        Tests = @()
        Score = 100
        Passed = $true
    }
    
    # Test 1: Agent répond
    $test1 = Test-AgentResponsive
    $validation.Tests += $test1
    if (!$test1.Passed) { $validation.Score -= 30 }
    
    # Test 2: Services critiques
    $test2 = Test-CriticalServices
    $validation.Tests += $test2
    if (!$test2.Passed) { $validation.Score -= 25 }
    
    # Test 3: SharePoint connectivité
    $test3 = Test-SharePointConnection
    $validation.Tests += $test3
    if (!$test3.Passed) { $validation.Score -= 20 }
    
    # Test 4: Métriques système
    $test4 = Test-SystemMetrics
    $validation.Tests += $test4
    if (!$test4.Passed) { $validation.Score -= 15 }
    
    # Test 5: Pas d'erreurs critiques
    $test5 = Test-NoErrors
    $validation.Tests += $test5
    if (!$test5.Passed) { $validation.Score -= 10 }
    
    # Déterminer résultat
    $validation.Passed = $validation.Score -ge 70
    
    if ($validation.Passed) {
        Write-Log "✅ Validation réussie (Score: $($validation.Score)/100)" "SUCCESS"
        $script:DeploymentState.ValidationStatus = "PASSED"
    } else {
        Write-Log "❌ Validation échouée (Score: $($validation.Score)/100)" "ERROR"
        $script:DeploymentState.ValidationStatus = "FAILED"
        
        # Ajouter à l'historique d'échecs
        $script:DeploymentState.FailureHistory += @{
            Version = $script:Version
            Timestamp = Get-Date
            Score = $validation.Score
            FailedTests = ($validation.Tests | Where-Object {!$_.Passed} | ForEach-Object {$_.Name})
        }
    }
    
    $script:ValidationResults += $validation
    Save-DeploymentState
    
    return $validation
}

function Test-AgentResponsive {
    $test = @{
        Name = "Agent Responsive"
        Passed = $false
        Details = ""
    }
    
    try {
        # Vérifier que l'agent peut exécuter des commandes
        $result = & powershell -Command "echo 'test'" 2>&1
        if ($result -eq "test") {
            $test.Passed = $true
            $test.Details = "Agent répond correctement"
        } else {
            $test.Details = "Agent ne répond pas"
        }
    } catch {
        $test.Details = "Erreur test: $_"
    }
    
    return $test
}

function Test-CriticalServices {
    $test = @{
        Name = "Critical Services"
        Passed = $true
        Details = @()
    }
    
    $criticalServices = @("W3SVC", "MSSQLSERVER", "VeeamBackupSvc")
    
    foreach ($svc in $criticalServices) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne "Running" -and $service.StartType -eq "Automatic") {
            $test.Passed = $false
            $test.Details += "$svc is stopped"
        }
    }
    
    if ($test.Passed) {
        $test.Details = "All critical services running"
    }
    
    return $test
}

function Test-SharePointConnection {
    $test = @{
        Name = "SharePoint Connection"
        Passed = $false
        Details = ""
    }
    
    try {
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded" `
            -TimeoutSec 10
        
        if ($tokenResponse.access_token) {
            $test.Passed = $true
            $test.Details = "SharePoint connection OK"
        }
    } catch {
        $test.Details = "SharePoint connection failed: $_"
    }
    
    return $test
}

function Test-SystemMetrics {
    $test = @{
        Name = "System Metrics"
        Passed = $true
        Details = @()
    }
    
    # CPU
    $cpu = (Get-Counter '\Processeur(_Total)\% temps processeur' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
    if ($cpu -gt 95) {
        $test.Passed = $false
        $test.Details += "CPU critical: $([math]::Round($cpu,1))%"
    }
    
    # Memory
    $os = Get-WmiObject Win32_OperatingSystem
    $memUsage = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
    if ($memUsage -gt 95) {
        $test.Passed = $false
        $test.Details += "Memory critical: $([math]::Round($memUsage,1))%"
    }
    
    # Disk
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
    $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    if ($diskFreeGB -lt 5) {
        $test.Passed = $false
        $test.Details += "Disk critical: ${diskFreeGB}GB free"
    }
    
    if ($test.Passed) {
        $test.Details = "System metrics normal"
    }
    
    return $test
}

function Test-NoErrors {
    $test = @{
        Name = "No Critical Errors"
        Passed = $true
        Details = ""
    }
    
    $errors = Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddMinutes(-5) -ErrorAction SilentlyContinue
    if ($errors -and $errors.Count -gt 10) {
        $test.Passed = $false
        $test.Details = "$($errors.Count) system errors in last 5 minutes"
    } else {
        $test.Details = "No critical errors detected"
    }
    
    return $test
}

# ════════════════════════════════════════════════════════════════════
# ROLLBACK AUTOMATIQUE
# ════════════════════════════════════════════════════════════════════
function Perform-AutoRollback {
    Write-Log "🚨 ROLLBACK AUTOMATIQUE DÉCLENCHÉ" "WARNING"
    
    # Chercher dernier snapshot valide
    $snapshots = Get-ChildItem "$($script:RollbackConfig.BackupPath)\snapshot-*" -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending
    
    if ($snapshots.Count -eq 0) {
        Write-Log "❌ Aucun snapshot disponible pour rollback" "ERROR"
        
        # Fallback vers version stable connue
        Write-Log "🔄 Tentative fallback vers v$($script:SafeVersion)..." "WARNING"
        Download-SafeVersion
        return
    }
    
    # Essayer chaque snapshot jusqu'à réussite
    foreach ($snapshot in $snapshots) {
        Write-Log "  Tentative avec: $($snapshot.Name)" "INFO"
        
        if (Restore-Snapshot $snapshot.FullName) {
            # Valider après restauration
            Start-Sleep -Seconds 5
            $postValidation = Validate-Deployment
            
            if ($postValidation.Passed) {
                Write-Log "✅ Rollback réussi et validé" "SUCCESS"
                Send-RollbackNotification "SUCCESS" $snapshot.Name
                return $true
            }
        }
    }
    
    Write-Log "❌ Tous les rollbacks ont échoué" "ERROR"
    Send-RollbackNotification "FAILED" "All attempts"
    return $false
}

function Download-SafeVersion {
    try {
        Write-Log "📥 Téléchargement version stable v$($script:SafeVersion)..." "INFO"
        
        $baseUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public"
        $agentUrl = "$baseUrl/agent-v$($script:SafeVersion).ps1"
        
        Invoke-WebRequest -Uri $agentUrl -OutFile "$atlasPath\agent.ps1" -UseBasicParsing
        
        Write-Log "✅ Version stable installée" "SUCCESS"
        
        # Forcer redémarrage
        Restart-Service "SYAGA-ATLAS-Agent" -Force -ErrorAction SilentlyContinue
        
    } catch {
        Write-Log "❌ Impossible de télécharger version stable: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════
function Get-ServiceStates {
    $services = @{}
    $critical = @("W3SVC", "MSSQLSERVER", "MSExchangeIS", "vmms", "VeeamBackupSvc")
    
    foreach ($svc in $critical) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            $services[$svc] = @{
                Status = $service.Status.ToString()
                StartType = $service.StartType.ToString()
            }
        }
    }
    
    return $services
}

function Get-ProcessSnapshot {
    Get-Process | Select-Object -First 10 Name, Id, WorkingSet64, CPU |
        ForEach-Object {
            @{
                Name = $_.Name
                PID = $_.Id
                MemoryMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
            }
        }
}

function Get-RegistrySnapshot {
    # Snapshot clés registry importantes
    @{
        ATLASVersion = (Get-ItemProperty "HKLM:\SOFTWARE\SYAGA\ATLAS" -Name Version -ErrorAction SilentlyContinue).Version
        WindowsVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ReleaseId).ReleaseId
    }
}

function Restore-Services($ServiceStates) {
    foreach ($svc in $ServiceStates.Keys) {
        $currentService = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($currentService) {
            if ($ServiceStates[$svc].Status -eq "Running" -and $currentService.Status -ne "Running") {
                Start-Service -Name $svc -ErrorAction SilentlyContinue
                Write-Log "  ✓ Service redémarré: $svc" "SUCCESS"
            }
        }
    }
}

function Clean-OldSnapshots {
    $snapshots = Get-ChildItem "$($script:RollbackConfig.BackupPath)\snapshot-*" -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending
    
    if ($snapshots.Count -gt $script:RollbackConfig.MaxBackups) {
        $toDelete = $snapshots | Select-Object -Skip $script:RollbackConfig.MaxBackups
        foreach ($old in $toDelete) {
            Remove-Item $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  Supprimé ancien snapshot: $($old.Name)" "DEBUG"
        }
    }
}

function Save-DeploymentState {
    try {
        $script:DeploymentState | ConvertTo-Json -Depth 10 |
            Set-Content $script:RollbackConfig.StateFile -Encoding UTF8
    } catch {
        Write-Log "Erreur sauvegarde état: $_" "WARNING"
    }
}

function Load-DeploymentState {
    if (Test-Path $script:RollbackConfig.StateFile) {
        try {
            $script:DeploymentState = Get-Content $script:RollbackConfig.StateFile -Raw | ConvertFrom-Json
        } catch {
            Write-Log "Erreur chargement état: $_" "WARNING"
        }
    }
}

function Send-RollbackNotification($Status, $Details) {
    try {
        # Envoyer notification à SharePoint
        $notification = @{
            Type = "ROLLBACK"
            Status = $Status
            Version = $script:Version
            Details = $Details
            Timestamp = Get-Date
            Server = $hostname
        }
        
        # Log local pour l'instant
        Write-Log "📧 Notification rollback: $Status - $Details" "INFO"
        
    } catch {
        Write-Log "Erreur notification: $_" "WARNING"
    }
}

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $script:LogsBuffer += "$logEntry`r`n"
    if ($script:LogsBuffer.Length -gt $script:MaxBufferSize) {
        $script:LogsBuffer = $script:LogsBuffer.Substring($script:LogsBuffer.Length - $script:MaxBufferSize)
    }
    
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        "DEBUG" { Write-Host $logEntry -ForegroundColor DarkGray }
        default { Write-Host $logEntry }
    }
}

# ════════════════════════════════════════════════════════════════════
# HEARTBEAT v16.0 AVEC ROLLBACK
# ════════════════════════════════════════════════════════════════════
function Send-Heartbeat {
    try {
        Write-Log "Préparation heartbeat v$($script:Version) avec rollback..." "DEBUG"
        
        # Token SharePoint
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
        
        # Métriques
        $cpu = (Get-Counter '\Processeur(_Total)\% temps processeur' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
        $os = Get-WmiObject Win32_OperatingSystem
        $memUsage = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        
        # IP
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        # Rapport rollback
        $rollbackReport = if ($script:DeploymentState.RollbackCount -gt 0) {
            "`r`n🔄 ROLLBACK INFO:`r`n" +
            "  Rollbacks: $($script:DeploymentState.RollbackCount)`r`n" +
            "  Current: v$($script:DeploymentState.CurrentVersion)`r`n" +
            "  Last Stable: v$($script:DeploymentState.LastStableVersion)`r`n" +
            "  Validation: $($script:DeploymentState.ValidationStatus)"
        } else { "" }
        
        # Validation report
        $validationReport = if ($script:ValidationResults.Count -gt 0) {
            $last = $script:ValidationResults[-1]
            "`r`n✅ VALIDATION:`r`n" +
            "  Score: $($last.Score)/100`r`n" +
            "  Tests: $($last.Tests.Count) ($(@($last.Tests | Where-Object {$_.Passed}).Count) passed)"
        } else { "" }
        
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logHeader = @"
════════════════════════════════════════════════════
ATLAS v$($script:Version) - ROLLBACK INTELLIGENT
════════════════════════════════════════════════════
Hostname: $hostname ($ip)
Time: $currentTime

MÉTRIQUES:
  CPU: $([math]::Round($cpu,1))%
  Memory: $([math]::Round($memUsage,1))%
  Disk C:\: $diskFreeGB GB free

$rollbackReport
$validationReport

LOGS RÉCENTS:
════════════════════════════════════════════════════
"@
        
        # Ajouter logs
        $enrichedLogs = $logHeader + "`r`n" + $script:LogsBuffer
        if ($enrichedLogs.Length -gt 8000) {
            $enrichedLogs = $enrichedLogs.Substring(0, 8000) + "`r`n... (tronqué)"
        }
        
        # Déterminer état
        $globalState = if ($script:DeploymentState.ValidationStatus -eq "FAILED") { "ROLLBACK" }
                      elseif ($script:DeploymentState.RollbackCount -gt 2) { "UNSTABLE" }
                      else { "HEALTHY" }
        
        # Données SharePoint
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname
            IPAddress = $ip
            State = $globalState
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = $script:Version
            CPUUsage = [math]::Round($cpu, 1)
            MemoryUsage = [math]::Round($memUsage, 1)
            DiskSpaceGB = $diskFreeGB
            Logs = $enrichedLogs
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        # Envoyer à SharePoint
        Write-Log "Envoi heartbeat v16.0 avec rollback status..." "DEBUG"
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-Log "Heartbeat v16.0 envoyé (État: $globalState)" "SUCCESS"
        
    } catch {
        Write-Log "Erreur heartbeat: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════════════════════
# MAIN v16.0
# ════════════════════════════════════════════════════════════════════
Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS v$($script:Version) - ROLLBACK INTELLIGENT" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

# Charger état précédent
Load-DeploymentState

# Si première exécution de cette version
if ($script:DeploymentState.CurrentVersion -ne $script:Version) {
    Write-Log "🆕 Nouveau déploiement détecté" "UPDATE"
    
    # Créer snapshot avant changements
    $snapshot = Create-Snapshot "Pre-v$($script:Version)"
    
    # Mettre à jour état
    $script:DeploymentState.CurrentVersion = $script:Version
    $script:DeploymentState.DeploymentTime = Get-Date
    $script:DeploymentState.ValidationStatus = "PENDING"
    Save-DeploymentState
    
    # Attendre un peu avant validation
    Write-Log "⏳ Attente stabilisation (10 secondes)..." "INFO"
    Start-Sleep -Seconds 10
    
    # Valider déploiement
    $validation = Validate-Deployment
    
    if (!$validation.Passed) {
        Write-Log "❌ Validation échouée - Rollback nécessaire" "ERROR"
        Perform-AutoRollback
    }
}

# Envoyer heartbeat
Send-Heartbeat

Write-Log "════════════════════════════════════════" "INFO"
Write-Log "ATLAS v$($script:Version) TERMINÉ" "SUCCESS"
Write-Log "════════════════════════════════════════" "INFO"

exit 0