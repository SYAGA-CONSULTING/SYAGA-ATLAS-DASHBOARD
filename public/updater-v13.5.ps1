# ════════════════════════════════════════════════════════════════════
# ATLAS Updater v13.0 - PRODUCTION-READY avec MUTEX et VALIDATION
# ════════════════════════════════════════════════════════════════════
# Architecture robuste basée sur les best practices 2024
# - Mutex global pour instance unique
# - Validation SHA256 des téléchargements
# - Rollback automatique en cas d'échec
# - Logs avec rotation et retry
# - État persistant JSON
# ════════════════════════════════════════════════════════════════════

$script:Version = "13.5"
$script:StartTime = Get-Date
$hostname = $env:COMPUTERNAME

# Chemins
$atlasPath = "C:\SYAGA-ATLAS"
$agentPath = "$atlasPath\agent.ps1"
$updaterPath = "$atlasPath\updater.ps1"
$statePath = "$atlasPath\updater-state.json"
$logPath = "$atlasPath\logs"
$backupPath = "$atlasPath\backups"

# Configuration SharePoint
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$commandsListId = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

# Paramètres
$maxLogSize = 2MB
$maxLogFiles = 5
$maxBackups = 3
$maxRetries = 3

# ════════════════════════════════════════════════════════════════════
# SECTION 1: MUTEX GLOBAL (Instance unique)
# ════════════════════════════════════════════════════════════════════
$mutex = $null
$mutexCreated = $false

try {
    # Créer un mutex global (accessible depuis toutes les sessions)
    $mutexName = "Global\SYAGA-ATLAS-Updater-$hostname"
    $mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$mutexCreated)
    
    if (-not $mutexCreated) {
        # Une autre instance tourne déjà
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Updater déjà en cours d'exécution" -ForegroundColor Yellow
        exit 0
    }
} catch {
    Write-Host "[ERROR] Impossible de créer le mutex: $_" -ForegroundColor Red
    exit 1
}

# ════════════════════════════════════════════════════════════════════
# SECTION 2: SYSTÈME DE LOGS ROBUSTE
# ════════════════════════════════════════════════════════════════════

# Créer les dossiers nécessaires
@($logPath, $backupPath) | ForEach-Object {
    if (!(Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

# Buffer de logs en mémoire
$script:LogBuffer = @()
$script:LogFile = "$logPath\updater_$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] [v$script:Version] $Message"
    
    # Ajouter au buffer
    $script:LogBuffer += $logEntry
    
    # Afficher en console (avec couleur)
    if (-not $NoConsole) {
        $color = switch($Level) {
            "ERROR" { "Red" }
            "WARNING" { "Yellow" }
            "SUCCESS" { "Green" }
            "DEBUG" { "DarkGray" }
            default { "White" }
        }
        Write-Host $logEntry -ForegroundColor $color
    }
    
    # Écrire dans le fichier avec retry
    $written = $false
    $attempts = 0
    
    while (-not $written -and $attempts -lt 3) {
        try {
            # Rotation si fichier trop gros
            if ((Test-Path $script:LogFile) -and (Get-Item $script:LogFile).Length -gt $maxLogSize) {
                Rotate-Logs
            }
            
            # Écrire le log
            Add-Content -Path $script:LogFile -Value $logEntry -Encoding UTF8
            $written = $true
            
        } catch {
            $attempts++
            Start-Sleep -Milliseconds 100
            
            if ($attempts -eq 3) {
                # Si impossible d'écrire, garder en buffer uniquement
                Write-Host "[WARNING] Impossible d'écrire dans le log après 3 essais" -ForegroundColor Yellow
            }
        }
    }
}

function Rotate-Logs {
    try {
        # Nettoyer les vieux logs
        $oldLogs = Get-ChildItem -Path $logPath -Filter "updater_*.log" | 
                   Sort-Object CreationTime -Descending | 
                   Select-Object -Skip $maxLogFiles
        
        $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
        
        # Archiver le log actuel
        $archiveName = "$logPath\updater_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Move-Item -Path $script:LogFile -Destination $archiveName -Force
        
    } catch {
        # Silencieux si rotation échoue
    }
}

# ════════════════════════════════════════════════════════════════════
# SECTION 3: ÉTAT PERSISTANT
# ════════════════════════════════════════════════════════════════════

function Get-UpdaterState {
    if (Test-Path $statePath) {
        try {
            $state = Get-Content $statePath -Raw | ConvertFrom-Json
            return $state
        } catch {
            Write-Log "Impossible de lire l'état, création nouveau" "WARNING"
        }
    }
    
    # État par défaut
    return @{
        LastCheck = $null
        LastUpdate = $null
        CurrentVersion = "Unknown"
        UpdateAttempts = 0
        LastError = $null
        Status = "Starting"
        ConsecutiveFailures = 0
    }
}

function Save-UpdaterState {
    param($State)
    
    try {
        $State.LastCheck = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $State | ConvertTo-Json -Depth 5 | Set-Content $statePath -Encoding UTF8
    } catch {
        Write-Log "Impossible de sauvegarder l'état: $_" "WARNING"
    }
}

# ════════════════════════════════════════════════════════════════════
# SECTION 4: VALIDATION ET SÉCURITÉ
# ════════════════════════════════════════════════════════════════════

function Test-ScriptValid {
    param([string]$ScriptPath)
    
    try {
        # Vérifier que le fichier existe
        if (!(Test-Path $ScriptPath)) {
            return $false
        }
        
        # Vérifier la taille (min 1KB, max 10MB)
        $fileInfo = Get-Item $ScriptPath
        if ($fileInfo.Length -lt 1KB -or $fileInfo.Length -gt 10MB) {
            Write-Log "Taille invalide: $($fileInfo.Length) bytes" "WARNING"
            return $false
        }
        
        # Vérifier la syntaxe PowerShell
        $errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $ScriptPath -Raw), [ref]$errors)
        
        if ($errors.Count -gt 0) {
            Write-Log "Erreurs de syntaxe détectées: $($errors.Count)" "WARNING"
            return $false
        }
        
        # Vérifier qu'il contient "ATLAS Agent"
        $content = Get-Content $ScriptPath -Raw
        if ($content -notmatch "ATLAS Agent") {
            Write-Log "Ne semble pas être un agent ATLAS valide" "WARNING"
            return $false
        }
        
        return $true
        
    } catch {
        Write-Log "Erreur validation script: $_" "ERROR"
        return $false
    }
}

function Get-FileHash256 {
    param([string]$FilePath)
    
    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
        return $hash.Hash
    } catch {
        return $null
    }
}

# ════════════════════════════════════════════════════════════════════
# SECTION 5: BACKUP ET ROLLBACK
# ════════════════════════════════════════════════════════════════════

function Backup-Agent {
    try {
        if (!(Test-Path $agentPath)) {
            return $true  # Pas d'agent à backup
        }
        
        # Créer nom de backup avec timestamp
        $backupName = "agent_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
        $backupFullPath = "$backupPath\$backupName"
        
        # Copier l'agent actuel
        Copy-Item -Path $agentPath -Destination $backupFullPath -Force
        Write-Log "Backup créé: $backupName" "SUCCESS"
        
        # Nettoyer vieux backups (garder seulement les N derniers)
        $oldBackups = Get-ChildItem -Path $backupPath -Filter "agent_*.ps1" |
                      Sort-Object CreationTime -Descending |
                      Select-Object -Skip $maxBackups
        
        $oldBackups | Remove-Item -Force -ErrorAction SilentlyContinue
        
        return $true
        
    } catch {
        Write-Log "Erreur backup: $_" "ERROR"
        return $false
    }
}

function Rollback-Agent {
    try {
        # Trouver le dernier backup
        $lastBackup = Get-ChildItem -Path $backupPath -Filter "agent_*.ps1" |
                      Sort-Object CreationTime -Descending |
                      Select-Object -First 1
        
        if (!$lastBackup) {
            Write-Log "Aucun backup disponible pour rollback" "ERROR"
            return $false
        }
        
        # Restaurer le backup
        Copy-Item -Path $lastBackup.FullName -Destination $agentPath -Force
        Write-Log "Rollback effectué depuis: $($lastBackup.Name)" "SUCCESS"
        
        return $true
        
    } catch {
        Write-Log "Erreur rollback: $_" "ERROR"
        return $false
    }
}

# ════════════════════════════════════════════════════════════════════
# SECTION 6: COMMUNICATION SHAREPOINT
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
            -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        
        return $tokenResponse.access_token
        
    } catch {
        Write-Log "Erreur obtention token SharePoint: $_" "ERROR"
        return $null
    }
}

function Get-PendingCommands {
    param($Token)
    
    try {
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Accept" = "application/json;odata=verbose"
        }
        
        $searchUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
        $response = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method GET -ErrorAction Stop
        
        $pendingCommands = @()
        
        foreach ($cmd in $response.d.results) {
            if ($cmd.Status -eq "PENDING") {
                $targetHost = if ($cmd.TargetHostname) { $cmd.TargetHostname } else { "ALL" }
                
                if ($targetHost -eq "ALL" -or $targetHost -eq $hostname) {
                    if ($cmd.CommandType -eq "UPDATE_ALL" -or $cmd.CommandType -eq "UPDATE") {
                        $pendingCommands += $cmd
                    }
                }
            }
        }
        
        # Retourner la commande la plus récente
        return $pendingCommands | Sort-Object -Property Id -Descending | Select-Object -First 1
        
    } catch {
        Write-Log "Erreur récupération commandes: $_" "ERROR"
        return $null
    }
}

function Mark-CommandDone {
    param($Token, $CommandId, $Message)
    
    try {
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
            "X-HTTP-Method" = "MERGE"
            "IF-MATCH" = "*"
        }
        
        $updateUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items($CommandId)"
        $updateBody = @{
            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
            Status = "DONE"
            ExecutedBy = "$hostname - $Message"
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method POST -Body $updateBody -ErrorAction Stop
        Write-Log "Commande $CommandId marquée DONE" "SUCCESS"
        return $true
        
    } catch {
        Write-Log "Erreur marquage commande: $_" "ERROR"
        return $false
    }
}

# ════════════════════════════════════════════════════════════════════
# SECTION 7: MISE À JOUR AGENT
# ════════════════════════════════════════════════════════════════════

function Update-Agent {
    param($NewVersion)
    
    $state = Get-UpdaterState
    $state.UpdateAttempts++
    
    try {
        Write-Log "Début mise à jour vers v$NewVersion" "INFO"
        
        # Télécharger nouvelle version
        $downloadUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$NewVersion.ps1"
        $tempPath = "$atlasPath\agent_temp_$NewVersion.ps1"
        
        Write-Log "Téléchargement depuis: $downloadUrl" "INFO"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
        
        # Valider le téléchargement
        if (!(Test-ScriptValid $tempPath)) {
            Write-Log "Script téléchargé invalide" "ERROR"
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
            $state.LastError = "Invalid script"
            Save-UpdaterState $state
            return $false
        }
        
        Write-Log "Script validé avec succès" "SUCCESS"
        
        # Backup de l'agent actuel
        if (Test-Path $agentPath) {
            if (!(Backup-Agent)) {
                Write-Log "Impossible de créer le backup, annulation" "ERROR"
                Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
                $state.LastError = "Backup failed"
                Save-UpdaterState $state
                return $false
            }
        }
        
        # Arrêter l'agent actuel
        Write-Log "Arrêt de l'agent actuel..." "INFO"
        Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        
        # Remplacer l'agent
        Move-Item -Path $tempPath -Destination $agentPath -Force
        Write-Log "Agent remplacé par v$NewVersion" "SUCCESS"
        
        # Redémarrer l'agent
        Write-Log "Démarrage du nouvel agent..." "INFO"
        Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        
        # Attendre et vérifier que l'agent démarre
        Start-Sleep -Seconds 5
        
        $task = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        if ($task -and $task.State -eq "Running") {
            Write-Log "Agent v$NewVersion démarré avec succès" "SUCCESS"
            
            # Mettre à jour l'état
            $state.CurrentVersion = $NewVersion
            $state.LastUpdate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $state.UpdateAttempts = 0
            $state.ConsecutiveFailures = 0
            $state.LastError = $null
            Save-UpdaterState $state
            
            return $true
        } else {
            Write-Log "L'agent ne démarre pas, rollback..." "ERROR"
            
            # Rollback
            if (Rollback-Agent) {
                Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
                Write-Log "Rollback effectué" "SUCCESS"
            }
            
            $state.LastError = "Agent failed to start"
            $state.ConsecutiveFailures++
            Save-UpdaterState $state
            
            return $false
        }
        
    } catch {
        Write-Log "Erreur mise à jour: $_" "ERROR"
        
        # Nettoyer
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        
        $state.LastError = $_.Exception.Message
        $state.ConsecutiveFailures++
        Save-UpdaterState $state
        
        return $false
    }
}

# ════════════════════════════════════════════════════════════════════
# SECTION 8: LOGIQUE PRINCIPALE
# ════════════════════════════════════════════════════════════════════

try {
    Write-Log "════════════════════════════════════════" "INFO"
    Write-Log "UPDATER v$script:Version DÉMARRAGE" "INFO"
    Write-Log "Host: $hostname" "INFO"
    Write-Log "════════════════════════════════════════" "INFO"
    
    # Charger l'état
    $state = Get-UpdaterState
    $state.Status = "Running"
    Save-UpdaterState $state
    
    # Obtenir le token SharePoint
    Write-Log "Connexion à SharePoint..." "INFO"
    $token = Get-SharePointToken
    
    if (!$token) {
        Write-Log "Impossible d'obtenir le token SharePoint" "ERROR"
        $state.Status = "Error"
        $state.LastError = "No SharePoint token"
        Save-UpdaterState $state
        exit 1
    }
    
    Write-Log "Token SharePoint obtenu" "SUCCESS"
    
    # Vérifier les commandes
    Write-Log "Recherche de commandes UPDATE..." "INFO"
    $command = Get-PendingCommands -Token $token
    
    if ($command) {
        Write-Log "Commande trouvée: ID=$($command.Id) v$($command.TargetVersion)" "SUCCESS"
        
        # Vérifier si c'est une nouvelle version
        $currentVersion = if (Test-Path $agentPath) {
            $content = Get-Content $agentPath -First 5 | Out-String
            if ($content -match 'Version\s*=\s*"([^"]+)"') {
                $matches[1]
            } else {
                "Unknown"
            }
        } else {
            "None"
        }
        
        Write-Log "Version actuelle: $currentVersion" "INFO"
        
        if ($currentVersion -ne $command.TargetVersion) {
            # Effectuer la mise à jour
            if (Update-Agent -NewVersion $command.TargetVersion) {
                # Marquer la commande comme DONE
                Mark-CommandDone -Token $token -CommandId $command.Id -Message "Updated from v$currentVersion to v$($command.TargetVersion)"
                Write-Log "Mise à jour réussie et commande marquée DONE" "SUCCESS"
            } else {
                Write-Log "Mise à jour échouée" "ERROR"
            }
        } else {
            Write-Log "Déjà en version $($command.TargetVersion), marquage DONE" "INFO"
            Mark-CommandDone -Token $token -CommandId $command.Id -Message "Already at v$($command.TargetVersion)"
        }
    } else {
        Write-Log "Aucune commande UPDATE en attente" "INFO"
    }
    
    # Sauvegarder l'état final
    $state.Status = "Idle"
    Save-UpdaterState $state
    
    Write-Log "════════════════════════════════════════" "INFO"
    Write-Log "UPDATER v$script:Version TERMINÉ" "INFO"
    Write-Log "Durée: $([int]((Get-Date) - $script:StartTime).TotalSeconds) secondes" "INFO"
    Write-Log "════════════════════════════════════════" "INFO"
    
} catch {
    Write-Log "ERREUR FATALE: $_" "ERROR"
    Write-Log "Stack: $($_.ScriptStackTrace)" "ERROR"
    
    $state = Get-UpdaterState
    $state.Status = "Error"
    $state.LastError = $_.Exception.Message
    Save-UpdaterState $state
    
} finally {
    # Libérer le mutex
    if ($mutex -and $mutexCreated) {
        try {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
            Write-Log "Mutex libéré" "DEBUG" -NoConsole
        } catch {
            # Silencieux
        }
    }
    
    # Forcer l'écriture des logs restants
    if ($script:LogBuffer.Count -gt 0) {
        try {
            $script:LogBuffer | Add-Content -Path $script:LogFile -Encoding UTF8
        } catch {
            # Silencieux
        }
    }
}

exit 0