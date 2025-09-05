# ════════════════════════════════════════════════════════════════════
# ATLAS ORCHESTRATOR v20.0 - ARCHITECTURE INSPIRÉE WAU
# ════════════════════════════════════════════════════════════════════
# Concepts inspirés de Winget-AutoUpdate mais code 100% original
# - Pas de remplacement de fichiers verrouillés
# - Téléchargement dans staging avant activation
# - Validation et rollback automatique
# ════════════════════════════════════════════════════════════════════

param(
    [string]$Mode = "Run"  # Run, Install, Update, Validate
)

$script:Version = "20.0"
$script:AtlasRoot = "C:\SYAGA-ATLAS"
$script:ConfigPath = "$script:AtlasRoot\config"
$script:RuntimePath = "$script:AtlasRoot\runtime"
$script:StagingPath = "$script:AtlasRoot\staging"
$script:BackupPath = "$script:AtlasRoot\backup"
$script:LogPath = "$script:AtlasRoot\logs"

# ════════════════════════════════════════════════════════════════════
# INITIALISATION STRUCTURE
# ════════════════════════════════════════════════════════════════════
function Initialize-AtlasStructure {
    $paths = @(
        $script:AtlasRoot,
        $script:ConfigPath,
        $script:RuntimePath,
        $script:StagingPath,
        $script:BackupPath,
        $script:LogPath
    )
    
    foreach ($path in $paths) {
        if (!(Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-AtlasLog "Créé: $path" "INIT"
        }
    }
    
    # Créer registre pour état persistant
    $regPath = "HKLM:\SOFTWARE\SYAGA\ATLAS"
    if (!(Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
        Set-ItemProperty -Path $regPath -Name "Version" -Value $script:Version
        Set-ItemProperty -Path $regPath -Name "InstallPath" -Value $script:AtlasRoot
        Set-ItemProperty -Path $regPath -Name "LastRun" -Value (Get-Date).ToString()
    }
}

# ════════════════════════════════════════════════════════════════════
# SYSTÈME DE LOGS ROTATIF
# ════════════════════════════════════════════════════════════════════
function Write-AtlasLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = "$script:LogPath\atlas-$(Get-Date -Format 'yyyy-MM-dd').log"
    
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Écrire dans fichier
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    
    # Afficher avec couleur
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "DEBUG" { "DarkGray" }
        default { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # Rotation logs > 30 jours
    Get-ChildItem "$script:LogPath\*.log" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ════════════════════════════════════════════════════════════════════
# DÉTECTION VERSION ACTUELLE
# ════════════════════════════════════════════════════════════════════
function Get-CurrentAtlasVersion {
    # 1. Vérifier registre Windows
    $regPath = "HKLM:\SOFTWARE\SYAGA\ATLAS"
    if (Test-Path $regPath) {
        $regVersion = Get-ItemProperty -Path $regPath -Name "Version" -ErrorAction SilentlyContinue
        if ($regVersion) {
            return $regVersion.Version
        }
    }
    
    # 2. Vérifier fichier de version
    $versionFile = "$script:ConfigPath\version.json"
    if (Test-Path $versionFile) {
        $versionData = Get-Content $versionFile -Raw | ConvertFrom-Json
        return $versionData.Version
    }
    
    # 3. Version par défaut
    return "20.0"
}

# ════════════════════════════════════════════════════════════════════
# TÉLÉCHARGEMENT DANS STAGING (PAS DIRECT)
# ════════════════════════════════════════════════════════════════════
function Download-NewVersion {
    param([string]$Version)
    
    Write-AtlasLog "Téléchargement v$Version dans staging..." "INFO"
    
    # Nettoyer staging
    Get-ChildItem $script:StagingPath -Recurse | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    
    $files = @{
        "agent.ps1" = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$Version.ps1"
        "updater.ps1" = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v$Version.ps1"
    }
    
    $success = $true
    
    foreach ($file in $files.Keys) {
        $stagingFile = "$script:StagingPath\$file"
        
        try {
            Invoke-WebRequest -Uri $files[$file] -OutFile $stagingFile -UseBasicParsing
            
            # Valider taille
            if ((Get-Item $stagingFile).Length -lt 1000) {
                Write-AtlasLog "Fichier trop petit: $file" "ERROR"
                $success = $false
            } else {
                Write-AtlasLog "✓ Téléchargé: $file" "SUCCESS"
            }
        } catch {
            Write-AtlasLog "Échec téléchargement $file : $_" "ERROR"
            $success = $false
        }
    }
    
    return $success
}

# ════════════════════════════════════════════════════════════════════
# VALIDATION AVANT ACTIVATION
# ════════════════════════════════════════════════════════════════════
function Test-StagedVersion {
    Write-AtlasLog "Validation version en staging..." "INFO"
    
    $tests = @{
        "Syntaxe PowerShell" = {
            $script = Get-Content "$script:StagingPath\agent.ps1" -Raw
            $errors = @()
            $null = [System.Management.Automation.PSParser]::Tokenize($script, [ref]$errors)
            return $errors.Count -eq 0
        }
        
        "Fichiers complets" = {
            $required = @("agent.ps1", "updater.ps1")
            foreach ($file in $required) {
                if (!(Test-Path "$script:StagingPath\$file")) {
                    return $false
                }
            }
            return $true
        }
        
        "Version correcte" = {
            $agentContent = Get-Content "$script:StagingPath\agent.ps1" -Raw
            return $agentContent -match '\$script:Version\s*=\s*"[\d\.]+"'
        }
    }
    
    $allPassed = $true
    
    foreach ($testName in $tests.Keys) {
        $result = & $tests[$testName]
        
        if ($result) {
            Write-AtlasLog "✓ $testName" "SUCCESS"
        } else {
            Write-AtlasLog "✗ $testName" "ERROR"
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# ════════════════════════════════════════════════════════════════════
# ACTIVATION NOUVELLE VERSION (ATOMIC)
# ════════════════════════════════════════════════════════════════════
function Activate-NewVersion {
    param([string]$Version)
    
    Write-AtlasLog "Activation v$Version..." "WARNING"
    
    try {
        # 1. Backup actuel
        $backupDir = "$script:BackupPath\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        
        if (Test-Path "$script:RuntimePath\agent.ps1") {
            Copy-Item "$script:RuntimePath\*" $backupDir -Recurse -Force
            Write-AtlasLog "Backup créé: $backupDir" "INFO"
        }
        
        # 2. Arrêter tâches
        Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # 3. Copier staging vers runtime
        Copy-Item "$script:StagingPath\*" $script:RuntimePath -Force
        
        # 4. Mettre à jour registre et config
        Set-ItemProperty -Path "HKLM:\SOFTWARE\SYAGA\ATLAS" -Name "Version" -Value $Version
        Set-ItemProperty -Path "HKLM:\SOFTWARE\SYAGA\ATLAS" -Name "LastUpdate" -Value (Get-Date).ToString()
        
        @{
            Version = $Version
            UpdatedAt = Get-Date
            UpdatedBy = "ATLAS-Orchestrator"
        } | ConvertTo-Json | Out-File "$script:ConfigPath\version.json" -Encoding UTF8
        
        # 5. Redémarrer tâches
        Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
        
        Write-AtlasLog "✓ Version $Version activée" "SUCCESS"
        return $true
        
    } catch {
        Write-AtlasLog "Échec activation: $_" "ERROR"
        
        # Rollback
        if ($backupDir -and (Test-Path $backupDir)) {
            Copy-Item "$backupDir\*" $script:RuntimePath -Force
            Write-AtlasLog "Rollback effectué" "WARNING"
        }
        
        return $false
    }
}

# ════════════════════════════════════════════════════════════════════
# CHECK SHAREPOINT POUR NOUVELLES VERSIONS
# ════════════════════════════════════════════════════════════════════
function Get-AvailableUpdate {
    $tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
    $clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
    $clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
    $clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
    $siteName = "syagacons"
    $commandsListId = "a056e76f-7947-465c-8356-dc6e18098f76"
    
    try {
        # Token
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $headers = @{
            "Authorization" = "Bearer $($tokenResponse.access_token)"
            "Accept" = "application/json;odata=verbose"
        }
        
        # Récupérer commandes
        $url = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method GET
        
        # Filtrer UPDATE pour ce serveur
        $updateCmd = $response.d.results | Where-Object {
            $_.Title -eq "UPDATE" -and 
            $_.Target -eq $env:COMPUTERNAME -and
            $_.Status -eq "PENDING"
        } | Select-Object -First 1
        
        if ($updateCmd) {
            Write-AtlasLog "Mise à jour disponible: v$($updateCmd.Version)" "INFO"
            
            # Marquer IN_PROGRESS
            $updateData = @{
                "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
                Status = "IN_PROGRESS"
                ExecutedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            } | ConvertTo-Json -Depth 10
            
            $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($($updateCmd.Id))"
            Invoke-RestMethod -Uri $updateUrl -Headers @{
                "Authorization" = $headers.Authorization
                "Accept" = "application/json;odata=verbose"
                "Content-Type" = "application/json;odata=verbose;charset=utf-8"
                "X-HTTP-Method" = "MERGE"
                "If-Match" = "*"
            } -Method POST -Body $updateData
            
            return @{
                Version = $updateCmd.Version
                CommandId = $updateCmd.Id
            }
        }
        
    } catch {
        Write-AtlasLog "Erreur check SharePoint: $_" "ERROR"
    }
    
    return $null
}

# ════════════════════════════════════════════════════════════════════
# MARQUER COMMANDE SHAREPOINT
# ════════════════════════════════════════════════════════════════════
function Set-CommandStatus {
    param(
        [int]$CommandId,
        [string]$Status
    )
    
    # Même config SharePoint
    $tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
    $clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
    $clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
    $clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
    $siteName = "syagacons"
    $commandsListId = "a056e76f-7947-465c-8356-dc6e18098f76"
    
    try {
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        
        $updateData = @{
            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
            Status = $Status
            ExecutedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        } | ConvertTo-Json -Depth 10
        
        $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($CommandId)"
        
        Invoke-RestMethod -Uri $updateUrl -Headers @{
            "Authorization" = "Bearer $($tokenResponse.access_token)"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
            "X-HTTP-Method" = "MERGE"
            "If-Match" = "*"
        } -Method POST -Body $updateData
        
        Write-AtlasLog "Commande $CommandId marquée: $Status" "INFO"
        
    } catch {
        Write-AtlasLog "Erreur marquage commande: $_" "ERROR"
    }
}

# ════════════════════════════════════════════════════════════════════
# PROCESSUS PRINCIPAL D'UPDATE
# ════════════════════════════════════════════════════════════════════
function Start-UpdateProcess {
    Write-AtlasLog "════════════════════════════════════════" "INFO"
    Write-AtlasLog "ATLAS ORCHESTRATOR v$($script:Version)" "INFO"
    Write-AtlasLog "════════════════════════════════════════" "INFO"
    
    $currentVersion = Get-CurrentAtlasVersion
    Write-AtlasLog "Version actuelle: v$currentVersion" "INFO"
    
    # Vérifier mise à jour disponible
    $update = Get-AvailableUpdate
    
    if ($update) {
        Write-AtlasLog "Mise à jour détectée: v$currentVersion → v$($update.Version)" "WARNING"
        
        # 1. Télécharger dans staging
        if (Download-NewVersion -Version $update.Version) {
            
            # 2. Valider
            if (Test-StagedVersion) {
                
                # 3. Activer
                if (Activate-NewVersion -Version $update.Version) {
                    
                    # 4. Marquer succès
                    Set-CommandStatus -CommandId $update.CommandId -Status "DONE"
                    Write-AtlasLog "✓ MISE À JOUR RÉUSSIE" "SUCCESS"
                    
                } else {
                    Set-CommandStatus -CommandId $update.CommandId -Status "FAILED"
                    Write-AtlasLog "✗ Échec activation" "ERROR"
                }
            } else {
                Set-CommandStatus -CommandId $update.CommandId -Status "FAILED"
                Write-AtlasLog "✗ Validation échouée" "ERROR"
            }
        } else {
            Set-CommandStatus -CommandId $update.CommandId -Status "FAILED"
            Write-AtlasLog "✗ Téléchargement échoué" "ERROR"
        }
    } else {
        Write-AtlasLog "Aucune mise à jour disponible" "DEBUG"
    }
    
    # Lancer agent actuel
    $agentPath = "$script:RuntimePath\agent.ps1"
    if (Test-Path $agentPath) {
        Write-AtlasLog "Exécution agent..." "INFO"
        & $agentPath
    }
}

# ════════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════════
Initialize-AtlasStructure

switch ($Mode) {
    "Install" {
        Write-AtlasLog "Installation ATLAS Orchestrator v$($script:Version)" "INFO"
        # Créer tâche planifiée
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode Run"
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration (New-TimeSpan -Days 365)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName "SYAGA-ATLAS-Orchestrator" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force
        Write-AtlasLog "✓ Tâche planifiée créée" "SUCCESS"
    }
    
    "Update" {
        # Forcer check update
        Start-UpdateProcess
    }
    
    "Validate" {
        # Mode test
        Test-StagedVersion
    }
    
    default {
        # Mode normal
        Start-UpdateProcess
    }
}

Write-AtlasLog "════════════════════════════════════════" "INFO"
Write-AtlasLog "Orchestrator terminé" "INFO"
Write-AtlasLog "════════════════════════════════════════════" "INFO"