# ════════════════════════════════════════════════════════════════════
# ATLAS UPDATER v14.0 - MONITORING TEMPS RÉEL AVANCÉ
# ════════════════════════════════════════════════════════════════════
# - Compatible avec agent v14.0
# - Détection services critiques
# - Auto-diagnostic problèmes
# ════════════════════════════════════════════════════════════════════

$script:Version = "14.0"
$hostname = $env:COMPUTERNAME
$atlasPath = "C:\SYAGA-ATLAS"

# Configuration SharePoint
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$commandsListId = "a056e76f-7947-465c-8356-dc6e18098f76"

# MUTEX 
$mutexName = "Global\SYAGA-ATLAS-UPDATER-v14.0"
$mutex = $null

# ════════════════════════════════════════════════════════════════════
# ÉTAT UPDATER 
# ════════════════════════════════════════════════════════════════════
$stateFile = "$atlasPath\updater-state.json"
$script:UpdaterState = @{
    LastCheck = $null
    LastUpdate = $null
    CurrentVersion = $script:Version
    Status = "CHECKING"
    ErrorCount = 0
}

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "UPDATE" { Write-Host $logEntry -ForegroundColor Magenta }
        "DEBUG" { Write-Host $logEntry -ForegroundColor DarkGray }
        "ALERT" { Write-Host $logEntry -ForegroundColor Red -BackgroundColor Yellow }
        default { Write-Host $logEntry }
    }
}

function Save-UpdaterState {
    try {
        $script:UpdaterState.LastCheck = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $script:UpdaterState | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
    } catch {
        Write-Log "Erreur sauvegarde état: $_" "WARNING"
    }
}

function Load-UpdaterState {
    if (Test-Path $stateFile) {
        try {
            $script:UpdaterState = Get-Content -Path $stateFile -Raw | ConvertFrom-Json
        } catch {
            Write-Log "Erreur chargement état: $_" "WARNING"
        }
    }
}

# ════════════════════════════════════════════════════════════════════
# FONCTIONS SHAREPOINT
# ════════════════════════════════════════════════════════════════════
function Get-SharePointToken {
    try {
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        return $tokenResponse.access_token
    } catch {
        Write-Log "Erreur token SharePoint: $_" "ERROR"
        return $null
    }
}

function Check-Updates {
    try {
        Write-Log "🔍 Vérification mises à jour v$($script:Version)..." "UPDATE"
        
        $token = Get-SharePointToken
        if (!$token) {
            Write-Log "Impossible d'obtenir le token" "ERROR"
            return
        }
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        # Récupérer commandes
        $url = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method GET
        
        # Filtrer commandes UPDATE pour ce serveur
        $updateCmd = $response.d.results | Where-Object {
            $_.Title -eq "UPDATE" -and 
            $_.Target -eq $hostname -and
            $_.Status -eq "PENDING"
        } | Select-Object -First 1
        
        if ($updateCmd) {
            Write-Log "📦 Mise à jour trouvée: v$($updateCmd.Version)" "UPDATE"
            
            # Marquer comme en cours
            Mark-Command $updateCmd.Id "IN_PROGRESS"
            
            # Télécharger et installer
            if (Install-Update $updateCmd.Version) {
                Mark-Command $updateCmd.Id "DONE"
                Write-Log "✅ Mise à jour v$($updateCmd.Version) installée" "SUCCESS"
                
                # Analyser services après update
                Analyze-ServiceHealth
                
                $script:UpdaterState.LastUpdate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $script:UpdaterState.CurrentVersion = $updateCmd.Version
                Save-UpdaterState
            } else {
                Mark-Command $updateCmd.Id "FAILED"
                Write-Log "❌ Échec mise à jour v$($updateCmd.Version)" "ERROR"
            }
        } else {
            Write-Log "Aucune mise à jour disponible" "DEBUG"
            
            # Vérifier santé services même sans update
            $health = Analyze-ServiceHealth
            if ($health.Issues.Count -gt 0) {
                Write-Log "⚠️ Problèmes détectés: $($health.Issues -join ', ')" "ALERT"
            }
        }
        
        # Nettoyer anciennes commandes
        Clean-OldCommands
        
    } catch {
        Write-Log "Erreur check updates: $_" "ERROR"
        $script:UpdaterState.ErrorCount++
    }
}

function Analyze-ServiceHealth {
    Write-Log "🔬 Analyse santé services..." "DEBUG"
    
    $health = @{
        Critical = @()
        Warning = @()
        Issues = @()
    }
    
    # Services critiques à vérifier
    $criticalServices = @(
        @{Name="W3SVC"; DisplayName="IIS"},
        @{Name="MSSQLSERVER"; DisplayName="SQL Server"},
        @{Name="MSExchangeIS"; DisplayName="Exchange"},
        @{Name="vmms"; DisplayName="Hyper-V"},
        @{Name="VeeamBackupSvc"; DisplayName="Veeam"}
    )
    
    foreach ($svc in $criticalServices) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne "Running" -and $service.StartType -eq "Automatic") {
                $health.Critical += $svc.DisplayName
                $health.Issues += "$($svc.DisplayName) arrêté"
                
                # Tentative auto-restart
                Write-Log "🔧 Tentative restart $($svc.DisplayName)..." "WARNING"
                try {
                    Start-Service -Name $svc.Name -ErrorAction Stop
                    Write-Log "✅ $($svc.DisplayName) redémarré" "SUCCESS"
                } catch {
                    Write-Log "❌ Impossible de redémarrer $($svc.DisplayName)" "ERROR"
                }
            }
        }
    }
    
    # Vérifier espace disque
    $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    if ($freeGB -lt 10) {
        $health.Critical += "Espace disque critique: ${freeGB}GB"
        $health.Issues += "Disque < 10GB"
        
        # Tentative nettoyage auto
        Write-Log "🧹 Nettoyage disque automatique..." "WARNING"
        Clear-DiskSpace
    } elseif ($freeGB -lt 50) {
        $health.Warning += "Espace disque bas: ${freeGB}GB"
    }
    
    # Log événements système
    $errors = Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddHours(-1) -ErrorAction SilentlyContinue
    if ($errors -and $errors.Count -gt 50) {
        $health.Warning += "$($errors.Count) erreurs système/heure"
        $health.Issues += "Erreurs système élevées"
    }
    
    return $health
}

function Clear-DiskSpace {
    try {
        # Nettoyer fichiers temporaires
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Nettoyer logs IIS anciens
        $iisLogs = "C:\inetpub\logs\LogFiles"
        if (Test-Path $iisLogs) {
            Get-ChildItem -Path $iisLogs -Recurse -File | 
                Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} | 
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        
        Write-Log "✅ Nettoyage disque effectué" "SUCCESS"
    } catch {
        Write-Log "Erreur nettoyage: $_" "WARNING"
    }
}

function Mark-Command($cmdId, $status) {
    try {
        $token = Get-SharePointToken
        if (!$token) { return }
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
            "X-HTTP-Method" = "MERGE"
            "If-Match" = "*"
        }
        
        $updateData = @{
            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
            Status = $status
            ExecutedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            ExecutedBy = "$hostname-UPDATER-v$($script:Version)"
        } | ConvertTo-Json -Depth 10
        
        $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($cmdId)"
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method POST -Body $updateData
        
        Write-Log "Commande $cmdId marquée: $status" "DEBUG"
        
    } catch {
        Write-Log "Erreur mark command: $_" "WARNING"
    }
}

function Install-Update($version) {
    try {
        Write-Log "📥 Installation v$version avec monitoring..." "UPDATE"
        
        # URLs
        $baseUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public"
        $agentUrl = "$baseUrl/agent-v$version.ps1"
        $updaterUrl = "$baseUrl/updater-v$version.ps1"
        
        # Backup actuel
        $backupPath = "$atlasPath\backup"
        if (!(Test-Path $backupPath)) {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        }
        
        Copy-Item "$atlasPath\agent.ps1" "$backupPath\agent-backup.ps1" -Force -ErrorAction SilentlyContinue
        Copy-Item "$atlasPath\updater.ps1" "$backupPath\updater-backup.ps1" -Force -ErrorAction SilentlyContinue
        
        # Télécharger nouveaux fichiers
        Invoke-WebRequest -Uri $agentUrl -OutFile "$atlasPath\agent-new.ps1" -UseBasicParsing
        Invoke-WebRequest -Uri $updaterUrl -OutFile "$atlasPath\updater-new.ps1" -UseBasicParsing
        
        # Valider téléchargements
        if ((Get-Item "$atlasPath\agent-new.ps1").Length -lt 1000) {
            throw "Agent téléchargé trop petit"
        }
        if ((Get-Item "$atlasPath\updater-new.ps1").Length -lt 1000) {
            throw "Updater téléchargé trop petit"
        }
        
        # Remplacer fichiers
        Move-Item "$atlasPath\agent-new.ps1" "$atlasPath\agent.ps1" -Force
        Move-Item "$atlasPath\updater-new.ps1" "$atlasPath\updater.ps1" -Force
        
        Write-Log "✅ Fichiers v$version installés" "SUCCESS"
        
        # Forcer exécution immédiate du nouvel agent
        Write-Log "🔄 Exécution agent v$version..." "UPDATE"
        & powershell.exe -ExecutionPolicy Bypass -File "$atlasPath\agent.ps1"
        
        return $true
        
    } catch {
        Write-Log "Erreur installation: $_" "ERROR"
        
        # Rollback si échec
        if (Test-Path "$backupPath\agent-backup.ps1") {
            Copy-Item "$backupPath\agent-backup.ps1" "$atlasPath\agent.ps1" -Force
            Copy-Item "$backupPath\updater-backup.ps1" "$atlasPath\updater.ps1" -Force
            Write-Log "⚠️ Rollback effectué" "WARNING"
        }
        
        return $false
    }
}

function Clean-OldCommands {
    try {
        $token = Get-SharePointToken
        if (!$token) { return }
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
        }
        
        # Récupérer toutes les commandes
        $url = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method GET
        
        # Nettoyer commandes de plus de 24h
        $oldDate = (Get-Date).AddHours(-24)
        $oldCommands = $response.d.results | Where-Object {
            $_.Target -eq $hostname -and
            $_.Status -eq "PENDING" -and
            [DateTime]$_.Created -lt $oldDate
        }
        
        foreach ($cmd in $oldCommands) {
            Mark-Command $cmd.Id "CANCELLED"
            Write-Log "Commande ancienne annulée: $($cmd.Title)" "DEBUG"
        }
        
    } catch {
        Write-Log "Erreur nettoyage: $_" "WARNING"
    }
}

# ════════════════════════════════════════════════════════════════════
# MAIN v14.0
# ════════════════════════════════════════════════════════════════════
try {
    # Mutex pour instance unique
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    if (!$mutex.WaitOne(0)) {
        Write-Log "Une instance est déjà en cours" "WARNING"
        exit 0
    }
    
    Write-Log "════════════════════════════════════════" "INFO"
    Write-Log "ATLAS UPDATER v$($script:Version) - MONITORING AVANCÉ" "SUCCESS"
    Write-Log "════════════════════════════════════════" "INFO"
    
    Load-UpdaterState
    
    # Vérifier mises à jour et santé
    Check-Updates
    
    Save-UpdaterState
    
    Write-Log "════════════════════════════════════════" "INFO"
    Write-Log "UPDATER v$($script:Version) TERMINÉ" "SUCCESS"
    Write-Log "════════════════════════════════════════" "INFO"
    
} catch {
    Write-Log "Erreur critique: $_" "ERROR"
    exit 1
} finally {
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

exit 0