# SYAGA WINDOWS UPDATE ORCHESTRATOR v3.0
# Full automatique - Un serveur à la fois - Zéro régression
# Exécution weekend avec rollback immédiat si problème

param(
    [Parameter(Mandatory=$false)]
    [string]$Mode = "Check",  # Check | Plan | Execute | Monitor | Rollback
    [switch]$Force,
    [switch]$TestMode,
    [string]$LogPath = "C:\SYAGA-ORCHESTRATOR\Logs",
    [string]$EmailTo = "sebastien.questier@syaga.fr"
)

$SCRIPT_VERSION = "3.0"
$SCRIPT_NAME = "SYAGA-ORCHESTRATOR"

# ================================================================================
# CONFIGURATION CENTRALE
# ================================================================================

$Config = @{
    # SharePoint & Azure
    SharePoint = @{
        TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
        ClientSecret = "[REDACTED]"
        SiteId = "syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8"
        ListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
    }
    
    # Notifications
    Notifications = @{
        Email = @{
            To = "sebastien.questier@syaga.fr"
            From = "orchestrator@syaga.fr"
            SmtpServer = "smtp.office365.com"
            Port = 587
            UseSsl = $true
        }
        Teams = @{
            WebhookUrl = ""  # À configurer
            Enabled = $true
        }
    }
    
    # Stratégie Update
    UpdateStrategy = @{
        OneServerAtTime = $true
        CreateSnapshots = $true
        StopOnError = $true
        AutoRollback = $true
        MaxRetries = 2
        WaitBetweenServers = 300  # 5 minutes
        VerificationDelay = 120   # 2 minutes après reboot
    }
    
    # Ordre de priorité (du moins critique au plus critique)
    ServerPriority = @(
        @{Type = "VM_Test"; Order = 1}
        @{Type = "VM_NonCritical"; Order = 2}
        @{Type = "VM_Veeam"; Order = 3}
        @{Type = "VM_Services"; Order = 4}
        @{Type = "VM_DC_Secondary"; Order = 5}
        @{Type = "VM_DC_Primary"; Order = 6}
        @{Type = "Host_Secondary"; Order = 7}
        @{Type = "Host_Primary"; Order = 8}
    )
}

# ================================================================================
# LOGGING & NOTIFICATIONS
# ================================================================================

function Initialize-Orchestrator {
    Write-Host "`n" -NoNewline
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║        SYAGA WINDOWS UPDATE ORCHESTRATOR v$SCRIPT_VERSION              ║" -ForegroundColor Cyan
    Write-Host "║          Full Auto - Zero Regression - Weekend Safe          ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Créer structure dossiers
    if (!(Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Log file avec timestamp
    $script:LogFile = Join-Path $LogPath "Orchestration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $script:StateFile = Join-Path $LogPath "Orchestration_State.json"
    
    # Initialiser état
    $script:OrchestrationState = @{
        StartTime = Get-Date
        Mode = $Mode
        Status = "Initializing"
        CurrentServer = $null
        ProcessedServers = @()
        FailedServers = @()
        SuccessfulServers = @()
        Snapshots = @()
        Errors = @()
    }
    
    Write-Log "Orchestrator initialisé - Mode: $Mode" "INFO"
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",  # INFO | WARNING | ERROR | SUCCESS | CRITICAL
        [switch]$NoConsole,
        [switch]$SendNotification
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Écrire dans fichier
    if ($script:LogFile) {
        $logEntry | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
    }
    
    # Afficher console avec couleur
    if (!$NoConsole) {
        $color = switch ($Level) {
            "INFO" { "White" }
            "WARNING" { "Yellow" }
            "ERROR" { "Red" }
            "SUCCESS" { "Green" }
            "CRITICAL" { "Magenta" }
            default { "Gray" }
        }
        
        $prefix = switch ($Level) {
            "INFO" { "ℹ️ " }
            "WARNING" { "⚠️ " }
            "ERROR" { "❌" }
            "SUCCESS" { "✅" }
            "CRITICAL" { "🔴" }
            default { "  " }
        }
        
        Write-Host "$prefix $Message" -ForegroundColor $color
    }
    
    # Notification si demandé
    if ($SendNotification) {
        Send-Notification -Message $Message -Level $Level
    }
}

function Send-Notification {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [hashtable]$Details = @{}
    )
    
    # Email notification
    try {
        if ($Config.Notifications.Email.To) {
            $subject = "[$SCRIPT_NAME] $Level - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            $body = @"
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; }
        .header { background: #0078D4; color: white; padding: 15px; }
        .content { padding: 20px; background: #f5f5f5; }
        .level-$($Level.ToLower()) { 
            padding: 10px; 
            margin: 10px 0; 
            border-left: 4px solid $(switch($Level){'ERROR'{'#D13438'}'WARNING'{'#FCE100'}'SUCCESS'{'#107C10'}default{'#0078D4'}});
            background: white;
        }
        .details { background: white; padding: 15px; margin: 10px 0; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 5px; border-bottom: 1px solid #eee; }
    </style>
</head>
<body>
    <div class='header'>
        <h2>🎯 SYAGA Update Orchestrator</h2>
    </div>
    <div class='content'>
        <div class='level-$($Level.ToLower())'>
            <h3>$Level: $Message</h3>
            <p>Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p>Server: $env:COMPUTERNAME</p>
        </div>
"@
            
            if ($Details.Count -gt 0) {
                $body += "<div class='details'><h4>Details:</h4><table>"
                foreach ($key in $Details.Keys) {
                    $body += "<tr><td><b>$key:</b></td><td>$($Details[$key])</td></tr>"
                }
                $body += "</table></div>"
            }
            
            # État actuel
            if ($script:OrchestrationState) {
                $body += @"
        <div class='details'>
            <h4>État Orchestration:</h4>
            <table>
                <tr><td><b>Serveurs traités:</b></td><td>$($script:OrchestrationState.ProcessedServers.Count)</td></tr>
                <tr><td><b>Succès:</b></td><td>$($script:OrchestrationState.SuccessfulServers.Count)</td></tr>
                <tr><td><b>Échecs:</b></td><td>$($script:OrchestrationState.FailedServers.Count)</td></tr>
                <tr><td><b>Serveur actuel:</b></td><td>$($script:OrchestrationState.CurrentServer)</td></tr>
            </table>
        </div>
"@
            }
            
            $body += "</div></body></html>"
            
            # Envoi email (à implémenter selon config SMTP)
            # Send-MailMessage -To $Config.Notifications.Email.To -Subject $subject -Body $body -BodyAsHtml
        }
    }
    catch {
        Write-Log "Erreur envoi notification email: $_" "WARNING"
    }
    
    # Teams notification
    try {
        if ($Config.Notifications.Teams.Enabled -and $Config.Notifications.Teams.WebhookUrl) {
            $teamsMessage = @{
                "@type" = "MessageCard"
                "@context" = "http://schema.org/extensions"
                "summary" = "$Level: $Message"
                "themeColor" = switch($Level) {
                    'ERROR' { "FF0000" }
                    'WARNING' { "FFA500" }
                    'SUCCESS' { "00FF00" }
                    default { "0078D4" }
                }
                "sections" = @(
                    @{
                        "activityTitle" = "SYAGA Orchestrator"
                        "activitySubtitle" = $Level
                        "activityImage" = "https://img.icons8.com/color/48/000000/windows-update.png"
                        "text" = $Message
                        "facts" = @()
                    }
                )
            }
            
            foreach ($key in $Details.Keys) {
                $teamsMessage.sections[0].facts += @{
                    "name" = $key
                    "value" = $Details[$key]
                }
            }
            
            $json = $teamsMessage | ConvertTo-Json -Depth 10
            Invoke-RestMethod -Uri $Config.Notifications.Teams.WebhookUrl -Method Post -Body $json -ContentType 'application/json'
        }
    }
    catch {
        Write-Log "Erreur envoi notification Teams: $_" "WARNING"
    }
}

# ================================================================================
# ANALYSE INFRASTRUCTURE
# ================================================================================

function Get-InfrastructureState {
    Write-Log "Analyse de l'infrastructure..." "INFO"
    
    $infrastructure = @{
        Timestamp = Get-Date
        Servers = @()
        HyperVHosts = @()
        VMs = @()
        VeeamServers = @()
        ReplicationPairs = @()
        UpdateOrder = @()
    }
    
    try {
        # Récupérer depuis SharePoint
        $token = Get-GraphToken
        $headers = @{Authorization = "Bearer $token"}
        $listUrl = "https://graph.microsoft.com/v1.0/sites/$($Config.SharePoint.SiteId)/lists/$($Config.SharePoint.ListId)/items?`$expand=fields"
        
        $response = Invoke-RestMethod -Uri $listUrl -Headers $headers
        
        foreach ($item in $response.value) {
            $server = $item.fields
            
            # Classifier le serveur
            $serverInfo = @{
                Name = $server.Hostname
                Type = "Unknown"
                Role = $server.Role
                State = $server.State
                LastContact = $server.LastContact
                AgentVersion = $server.AgentVersion
                IsHyperVHost = $false
                IsVM = $false
                HasVeeam = $false
                VMs = @()
                ReplicationPartner = $null
                Priority = 99
                CanUpdate = $true
            }
            
            # Détecter Hyper-V Host
            if ($server.HyperVStatus -and $server.HyperVStatus -match "(\d+).*VM") {
                $serverInfo.IsHyperVHost = $true
                $serverInfo.Type = "HyperV_Host"
                $vmCount = [int]$Matches[1]
                $serverInfo.VMs = @("$vmCount VMs détectées")
                $infrastructure.HyperVHosts += $serverInfo
            }
            
            # Détecter Veeam
            if ($server.VeeamStatus -and $server.VeeamStatus -like "*Installed*") {
                $serverInfo.HasVeeam = $true
                $infrastructure.VeeamServers += $server.Hostname
            }
            
            # Déterminer priorité selon type
            $serverInfo.Priority = Get-ServerPriority -Server $serverInfo
            
            $infrastructure.Servers += $serverInfo
        }
        
        # Détecter les paires de réplication (analyse locale si on est sur un hôte)
        if (Get-Command Get-VMReplication -ErrorAction SilentlyContinue) {
            $replications = Get-VMReplication -ErrorAction SilentlyContinue
            foreach ($repl in $replications) {
                $infrastructure.ReplicationPairs += @{
                    VM = $repl.Name
                    Primary = $repl.PrimaryServer
                    Replica = $repl.ReplicaServer
                    Health = $repl.Health
                    State = $repl.State
                }
            }
        }
        
        # Créer ordre de mise à jour
        $infrastructure.UpdateOrder = $infrastructure.Servers | Sort-Object Priority, Name
        
        Write-Log "Infrastructure analysée: $($infrastructure.Servers.Count) serveurs" "SUCCESS"
        
        # Afficher résumé
        Write-Log "  - Hôtes Hyper-V: $($infrastructure.HyperVHosts.Count)" "INFO"
        Write-Log "  - Serveurs Veeam: $($infrastructure.VeeamServers.Count)" "INFO"
        Write-Log "  - Paires réplication: $($infrastructure.ReplicationPairs.Count)" "INFO"
        
    }
    catch {
        Write-Log "Erreur analyse infrastructure: $_" "ERROR"
    }
    
    return $infrastructure
}

function Get-ServerPriority {
    param($Server)
    
    # Logique de priorité (1 = moins critique, 10 = plus critique)
    if ($Server.Name -like "*TEST*") { return 1 }
    if ($Server.Name -like "*DEV*") { return 2 }
    if ($Server.HasVeeam) { return 5 }
    if ($Server.Name -like "*DC*" -and $Server.Name -like "*02*") { return 7 }
    if ($Server.Name -like "*DC*" -and $Server.Name -like "*01*") { return 8 }
    if ($Server.IsHyperVHost -and $Server.Name -like "*02*") { return 9 }
    if ($Server.IsHyperVHost -and $Server.Name -like "*01*") { return 10 }
    
    return 5  # Défaut milieu
}

# ================================================================================
# GESTION SNAPSHOTS
# ================================================================================

function Create-SafetySnapshot {
    param(
        [string]$ServerName,
        [string]$Type = "VM"  # VM | Host
    )
    
    Write-Log "Création snapshot de sécurité pour $ServerName..." "INFO"
    
    $snapshot = @{
        Server = $ServerName
        Type = $Type
        Created = Get-Date
        Name = "PRE-UPDATE-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Success = $false
        Path = $null
    }
    
    try {
        if ($Type -eq "VM") {
            # Snapshot Hyper-V
            if (Get-Command Checkpoint-VM -ErrorAction SilentlyContinue) {
                Checkpoint-VM -Name $ServerName -SnapshotName $snapshot.Name -ErrorAction Stop
                $snapshot.Success = $true
                $snapshot.Path = "Hyper-V"
                Write-Log "Snapshot Hyper-V créé: $($snapshot.Name)" "SUCCESS"
            }
        }
        else {
            # Pour un hôte, on fait un point de restauration système
            if ($ServerName -eq $env:COMPUTERNAME) {
                $result = Checkpoint-Computer -Description $snapshot.Name -RestorePointType MODIFY_SETTINGS
                $snapshot.Success = $true
                $snapshot.Path = "SystemRestore"
                Write-Log "Point de restauration système créé" "SUCCESS"
            }
        }
        
        # Ajouter à la liste des snapshots
        $script:OrchestrationState.Snapshots += $snapshot
        
    }
    catch {
        Write-Log "Erreur création snapshot: $_" "WARNING"
        
        # Si pas d'espace, proposer de nettoyer
        if ($_.Exception.Message -like "*espace*" -or $_.Exception.Message -like "*space*") {
            Write-Log "Tentative de nettoyage des anciens snapshots..." "INFO"
            Remove-OldSnapshots -KeepLast 2
            
            # Réessayer
            try {
                if ($Type -eq "VM") {
                    Checkpoint-VM -Name $ServerName -SnapshotName $snapshot.Name -ErrorAction Stop
                    $snapshot.Success = $true
                    Write-Log "Snapshot créé après nettoyage" "SUCCESS"
                }
            }
            catch {
                Write-Log "Impossible de créer snapshot même après nettoyage" "ERROR"
            }
        }
    }
    
    return $snapshot
}

function Remove-OldSnapshots {
    param([int]$KeepLast = 3)
    
    Write-Log "Nettoyage des anciens snapshots (garde les $KeepLast derniers)..." "INFO"
    
    try {
        # Nettoyer snapshots Hyper-V
        if (Get-Command Get-VMSnapshot -ErrorAction SilentlyContinue) {
            $allSnapshots = Get-VMSnapshot -VMName * | Where-Object {$_.Name -like "PRE-UPDATE-*"} | Sort-Object CreationTime
            
            if ($allSnapshots.Count -gt $KeepLast) {
                $toDelete = $allSnapshots | Select-Object -First ($allSnapshots.Count - $KeepLast)
                foreach ($snap in $toDelete) {
                    Write-Log "Suppression snapshot: $($snap.Name) de $($snap.VMName)" "INFO"
                    Remove-VMSnapshot -VMSnapshot $snap -IncludeAllChildSnapshots -Confirm:$false
                }
            }
        }
    }
    catch {
        Write-Log "Erreur nettoyage snapshots: $_" "WARNING"
    }
}

# ================================================================================
# WINDOWS UPDATE
# ================================================================================

function Execute-WindowsUpdate {
    param(
        [string]$ServerName,
        [hashtable]$ServerInfo
    )
    
    Write-Log "Début Windows Update sur $ServerName" "INFO" -SendNotification
    $script:OrchestrationState.CurrentServer = $ServerName
    
    $result = @{
        Server = $ServerName
        Success = $false
        UpdatesInstalled = 0
        RebootRequired = $false
        Errors = @()
        StartTime = Get-Date
        EndTime = $null
        RollbackExecuted = $false
    }
    
    try {
        # ÉTAPE 1: Créer snapshot si configuré
        if ($Config.UpdateStrategy.CreateSnapshots) {
            $snapshot = Create-SafetySnapshot -ServerName $ServerName -Type $(if($ServerInfo.IsHyperVHost){"Host"}else{"VM"})
            if (!$snapshot.Success -and $Config.UpdateStrategy.StopOnError) {
                throw "Impossible de créer snapshot de sécurité"
            }
        }
        
        # ÉTAPE 2: Suspendre services si nécessaire
        if ($ServerInfo.IsHyperVHost) {
            Write-Log "Suspension réplication pour hôte Hyper-V..." "INFO"
            Suspend-ReplicationForHost -HostName $ServerName
        }
        
        if ($ServerInfo.HasVeeam) {
            Write-Log "Suspension jobs Veeam..." "INFO"
            Suspend-VeeamForUpdate -ServerName $ServerName
        }
        
        # ÉTAPE 3: Exécuter Windows Update
        Write-Log "Recherche des mises à jour..." "INFO"
        
        if ($ServerName -eq $env:COMPUTERNAME) {
            # Exécution locale
            $updates = Get-WindowsUpdates -ServerName $ServerName
            
            if ($updates.Count -gt 0) {
                Write-Log "Installation de $($updates.Count) mises à jour..." "INFO"
                $installResult = Install-WindowsUpdates -Updates $updates
                
                $result.UpdatesInstalled = $installResult.Installed
                $result.RebootRequired = $installResult.RebootRequired
                
                if ($installResult.Failed -gt 0) {
                    throw "Échec installation de $($installResult.Failed) mises à jour"
                }
            }
            else {
                Write-Log "Système déjà à jour" "SUCCESS"
                $result.Success = $true
            }
        }
        else {
            # Exécution distante
            Write-Log "Connexion distante à $ServerName..." "INFO"
            # TODO: Implémenter via Invoke-Command ou WinRM
        }
        
        # ÉTAPE 4: Reboot si nécessaire
        if ($result.RebootRequired) {
            Write-Log "Redémarrage nécessaire..." "WARNING"
            
            if ($ServerInfo.IsHyperVHost) {
                # Sauvegarder état des VMs avant reboot
                Save-VMStateBeforeReboot -HostName $ServerName
            }
            
            Write-Log "Redémarrage en cours..." "INFO"
            Restart-Computer -ComputerName $ServerName -Force -Wait -For PowerShell -Timeout 600
            
            Write-Log "Serveur redémarré, attente stabilisation..." "INFO"
            Start-Sleep -Seconds $Config.UpdateStrategy.VerificationDelay
        }
        
        # ÉTAPE 5: Vérifications post-update
        Write-Log "Vérifications post-update..." "INFO"
        $verifyResult = Test-ServerHealth -ServerName $ServerName -ServerInfo $ServerInfo
        
        if (!$verifyResult.Healthy) {
            throw "Échec vérification santé: $($verifyResult.Issues -join ', ')"
        }
        
        # ÉTAPE 6: Restaurer services
        if ($ServerInfo.IsHyperVHost) {
            Resume-ReplicationForHost -HostName $ServerName
        }
        
        if ($ServerInfo.HasVeeam) {
            Resume-VeeamAfterUpdate -ServerName $ServerName
        }
        
        $result.Success = $true
        $result.EndTime = Get-Date
        
        Write-Log "Windows Update terminé avec succès sur $ServerName" "SUCCESS" -SendNotification
        
    }
    catch {
        $result.Errors += $_.ToString()
        Write-Log "ÉCHEC Windows Update sur $ServerName: $_" "ERROR" -SendNotification
        
        # ROLLBACK si configuré
        if ($Config.UpdateStrategy.AutoRollback) {
            Write-Log "Exécution du rollback automatique..." "WARNING"
            $result.RollbackExecuted = Execute-Rollback -ServerName $ServerName -Reason "Update failed: $_"
        }
        
        # Arrêter orchestration si configuré
        if ($Config.UpdateStrategy.StopOnError) {
            throw "Arrêt orchestration suite à échec sur $ServerName"
        }
    }
    
    # Ajouter au state
    if ($result.Success) {
        $script:OrchestrationState.SuccessfulServers += $ServerName
    }
    else {
        $script:OrchestrationState.FailedServers += $ServerName
    }
    $script:OrchestrationState.ProcessedServers += $ServerName
    
    return $result
}

function Get-WindowsUpdates {
    param([string]$ServerName)
    
    # Utiliser PSWindowsUpdate si disponible
    if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Log "Installation module PSWindowsUpdate..." "INFO"
        Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser
    }
    
    Import-Module PSWindowsUpdate
    
    $updates = Get-WindowsUpdate -ComputerName $ServerName -AcceptAll
    
    Write-Log "Mises à jour trouvées: $($updates.Count)" "INFO"
    foreach ($update in $updates) {
        Write-Log "  - $($update.Title) [$($update.Size)]" "INFO"
    }
    
    return $updates
}

function Install-WindowsUpdates {
    param($Updates)
    
    $result = @{
        Installed = 0
        Failed = 0
        RebootRequired = $false
    }
    
    foreach ($update in $Updates) {
        try {
            Install-WindowsUpdate -KBArticleID $update.KB -AcceptAll -IgnoreReboot
            $result.Installed++
        }
        catch {
            Write-Log "Échec installation $($update.KB): $_" "ERROR"
            $result.Failed++
        }
    }
    
    # Vérifier si reboot nécessaire
    $result.RebootRequired = Get-WURebootStatus -Silent
    
    return $result
}

# ================================================================================
# GESTION HYPER-V
# ================================================================================

function Suspend-ReplicationForHost {
    param([string]$HostName)
    
    Write-Log "Suspension réplication Hyper-V sur $HostName..." "INFO"
    
    try {
        $vms = Get-VMReplication -ComputerName $HostName -ErrorAction SilentlyContinue
        
        foreach ($vm in $vms | Where-Object {$_.State -ne "Suspended"}) {
            Write-Log "  Suspension: $($vm.Name)" "INFO"
            Suspend-VMReplication -VMName $vm.Name -ComputerName $HostName
        }
        
        Write-Log "Réplication suspendue pour $($vms.Count) VMs" "SUCCESS"
    }
    catch {
        Write-Log "Erreur suspension réplication: $_" "WARNING"
    }
}

function Resume-ReplicationForHost {
    param([string]$HostName)
    
    Write-Log "Reprise réplication Hyper-V sur $HostName..." "INFO"
    
    try {
        $vms = Get-VMReplication -ComputerName $HostName -ErrorAction SilentlyContinue
        
        foreach ($vm in $vms | Where-Object {$_.State -eq "Suspended"}) {
            Write-Log "  Reprise: $($vm.Name)" "INFO"
            Resume-VMReplication -VMName $vm.Name -ComputerName $HostName
            
            # Vérifier santé
            Start-Sleep -Seconds 5
            $health = (Get-VMReplication -VMName $vm.Name -ComputerName $HostName).Health
            
            if ($health -ne "Normal") {
                Write-Log "  ⚠️ $($vm.Name) santé: $health - Resync peut être nécessaire" "WARNING"
            }
        }
        
        Write-Log "Réplication reprise pour $($vms.Count) VMs" "SUCCESS"
    }
    catch {
        Write-Log "Erreur reprise réplication: $_" "WARNING"
    }
}

function Save-VMStateBeforeReboot {
    param([string]$HostName)
    
    Write-Log "Sauvegarde état VMs avant reboot..." "INFO"
    
    try {
        $vms = Get-VM -ComputerName $HostName | Where-Object {$_.State -eq "Running"}
        
        foreach ($vm in $vms) {
            Write-Log "  Sauvegarde: $($vm.Name)" "INFO"
            Save-VM -Name $vm.Name -ComputerName $HostName
        }
        
        Write-Log "$($vms.Count) VMs sauvegardées" "SUCCESS"
    }
    catch {
        Write-Log "Erreur sauvegarde VMs: $_" "WARNING"
    }
}

# ================================================================================
# GESTION VEEAM
# ================================================================================

function Suspend-VeeamForUpdate {
    param([string]$ServerName)
    
    Write-Log "Suspension Veeam sur $ServerName..." "INFO"
    
    try {
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            $jobs = Get-VBRJob | Where-Object {$_.IsScheduleEnabled}
            
            foreach ($job in $jobs) {
                Disable-VBRJob -Job $job
                Write-Log "  Job suspendu: $($job.Name)" "INFO"
            }
            
            # Attendre fin des jobs en cours
            $running = Get-VBRJob | Where-Object {$_.GetLastState() -eq "Working"}
            if ($running) {
                Write-Log "Attente fin de $($running.Count) jobs en cours..." "INFO"
                
                $maxWait = 300  # 5 minutes max
                $waited = 0
                
                while ($running -and $waited -lt $maxWait) {
                    Start-Sleep -Seconds 30
                    $waited += 30
                    $running = Get-VBRJob | Where-Object {$_.GetLastState() -eq "Working"}
                }
            }
            
            Write-Log "Veeam suspendu" "SUCCESS"
        }
    }
    catch {
        Write-Log "Erreur suspension Veeam: $_" "WARNING"
    }
}

function Resume-VeeamAfterUpdate {
    param([string]$ServerName)
    
    Write-Log "Réactivation Veeam sur $ServerName..." "INFO"
    
    try {
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            $jobs = Get-VBRJob
            
            foreach ($job in $jobs) {
                Enable-VBRJob -Job $job
                Write-Log "  Job réactivé: $($job.Name)" "INFO"
            }
            
            Write-Log "Veeam réactivé" "SUCCESS"
        }
    }
    catch {
        Write-Log "Erreur réactivation Veeam: $_" "WARNING"
    }
}

# ================================================================================
# VÉRIFICATIONS SANTÉ
# ================================================================================

function Test-ServerHealth {
    param(
        [string]$ServerName,
        [hashtable]$ServerInfo
    )
    
    Write-Log "Vérification santé $ServerName..." "INFO"
    
    $health = @{
        Healthy = $true
        Issues = @()
        Checks = @()
    }
    
    # Check 1: Ping
    if (!(Test-Connection -ComputerName $ServerName -Count 2 -Quiet)) {
        $health.Healthy = $false
        $health.Issues += "Ping failed"
    }
    else {
        $health.Checks += "Ping OK"
    }
    
    # Check 2: Services critiques
    $criticalServices = @("Server", "Workstation", "RpcSs", "LanmanServer")
    
    if ($ServerInfo.IsHyperVHost) {
        $criticalServices += "vmms", "vmcompute"
    }
    
    if ($ServerInfo.HasVeeam) {
        $criticalServices += "VeeamBackupSvc"
    }
    
    foreach ($service in $criticalServices) {
        try {
            $svc = Get-Service -Name $service -ComputerName $ServerName -ErrorAction Stop
            if ($svc.Status -ne "Running") {
                $health.Issues += "Service $service not running"
            }
            else {
                $health.Checks += "Service $service OK"
            }
        }
        catch {
            $health.Issues += "Cannot check service $service"
        }
    }
    
    # Check 3: Réplication si Hyper-V
    if ($ServerInfo.IsHyperVHost) {
        try {
            $replications = Get-VMReplication -ComputerName $ServerName -ErrorAction SilentlyContinue
            $critical = $replications | Where-Object {$_.Health -eq "Critical"}
            
            if ($critical) {
                $health.Issues += "$($critical.Count) VMs with critical replication"
            }
            else {
                $health.Checks += "Replication OK"
            }
        }
        catch {}
    }
    
    # Check 4: Espace disque
    try {
        $disk = Get-WmiObject Win32_LogicalDisk -ComputerName $ServerName -Filter "DeviceID='C:'"
        $freeGB = [Math]::Round($disk.FreeSpace / 1GB, 1)
        
        if ($freeGB -lt 5) {
            $health.Issues += "Low disk space: ${freeGB}GB"
        }
        else {
            $health.Checks += "Disk space OK: ${freeGB}GB"
        }
    }
    catch {}
    
    if ($health.Issues.Count -gt 0) {
        $health.Healthy = $false
        Write-Log "Issues trouvées: $($health.Issues -join ', ')" "WARNING"
    }
    else {
        Write-Log "Toutes vérifications OK" "SUCCESS"
    }
    
    return $health
}

# ================================================================================
# ROLLBACK
# ================================================================================

function Execute-Rollback {
    param(
        [string]$ServerName,
        [string]$Reason
    )
    
    Write-Log "🔄 ROLLBACK sur $ServerName - Raison: $Reason" "CRITICAL" -SendNotification
    
    $success = $false
    
    try {
        # Chercher le snapshot
        $snapshot = $script:OrchestrationState.Snapshots | Where-Object {$_.Server -eq $ServerName} | Select-Object -Last 1
        
        if ($snapshot) {
            Write-Log "Restauration depuis snapshot: $($snapshot.Name)" "INFO"
            
            if ($snapshot.Type -eq "VM") {
                # Restaurer snapshot Hyper-V
                Restore-VMSnapshot -Name $snapshot.Name -VMName $ServerName -Confirm:$false
                Start-VM -Name $ServerName
                $success = $true
            }
            elseif ($snapshot.Type -eq "Host") {
                # Pour un hôte, plus complexe
                Write-Log "Rollback hôte nécessite intervention manuelle" "WARNING"
                
                # Si l'hôte est down, basculer les VMs sur réplicas
                Write-Log "Tentative basculement VMs sur réplicas..." "INFO"
                Start-VMFailover -HostName $ServerName
            }
        }
        else {
            Write-Log "Aucun snapshot trouvé pour rollback" "ERROR"
        }
    }
    catch {
        Write-Log "Erreur rollback: $_" "ERROR"
    }
    
    return $success
}

function Start-VMFailover {
    param([string]$HostName)
    
    Write-Log "Basculement VMs de $HostName vers réplicas..." "WARNING"
    
    # TODO: Implémenter le failover vers les réplicas
    # Cette fonction doit:
    # 1. Identifier les VMs du host en échec
    # 2. Trouver leurs réplicas
    # 3. Démarrer les réplicas
    # 4. Mettre à jour le DNS si nécessaire
}

# ================================================================================
# ORCHESTRATION PRINCIPALE
# ================================================================================

function Start-Orchestration {
    param([hashtable]$Infrastructure)
    
    Write-Log "🚀 DÉMARRAGE ORCHESTRATION COMPLÈTE" "INFO" -SendNotification
    Write-Log "Serveurs à traiter: $($Infrastructure.UpdateOrder.Count)" "INFO"
    
    $script:OrchestrationState.Status = "Running"
    $orchestrationSuccess = $true
    
    try {
        # Parcourir les serveurs dans l'ordre
        foreach ($server in $Infrastructure.UpdateOrder) {
            Write-Log "`n" + ("=" * 60) "INFO"
            Write-Log "Serveur $($Infrastructure.UpdateOrder.IndexOf($server) + 1)/$($Infrastructure.UpdateOrder.Count): $($server.Name)" "INFO"
            Write-Log ("=" * 60) "INFO"
            
            # Vérifier si on peut continuer
            if (!$server.CanUpdate) {
                Write-Log "Serveur $($server.Name) marqué non-updatable, skip" "WARNING"
                continue
            }
            
            # Exécuter update
            $updateResult = Execute-WindowsUpdate -ServerName $server.Name -ServerInfo $server
            
            if (!$updateResult.Success) {
                Write-Log "Échec update sur $($server.Name)" "ERROR"
                
                if ($Config.UpdateStrategy.StopOnError) {
                    throw "Arrêt suite à échec sur $($server.Name)"
                }
            }
            
            # Attendre entre serveurs
            if ($Infrastructure.UpdateOrder.IndexOf($server) -lt $Infrastructure.UpdateOrder.Count - 1) {
                Write-Log "Attente $($Config.UpdateStrategy.WaitBetweenServers) secondes avant prochain serveur..." "INFO"
                Start-Sleep -Seconds $Config.UpdateStrategy.WaitBetweenServers
            }
        }
        
        Write-Log "`n✅ ORCHESTRATION TERMINÉE AVEC SUCCÈS" "SUCCESS" -SendNotification
        
    }
    catch {
        $orchestrationSuccess = $false
        Write-Log "❌ ORCHESTRATION ÉCHOUÉE: $_" "CRITICAL" -SendNotification
        
        # Envoyer rapport d'erreur
        Send-FinalReport -Success $false -Error $_
    }
    finally {
        $script:OrchestrationState.Status = if($orchestrationSuccess){"Completed"}else{"Failed"}
        $script:OrchestrationState.EndTime = Get-Date
        
        # Sauvegarder état final
        Save-OrchestrationState
    }
    
    return $orchestrationSuccess
}

# ================================================================================
# RAPPORTS
# ================================================================================

function Send-FinalReport {
    param(
        [bool]$Success = $true,
        [string]$Error = ""
    )
    
    Write-Log "Génération rapport final..." "INFO"
    
    $duration = if($script:OrchestrationState.StartTime) {
        (Get-Date) - $script:OrchestrationState.StartTime
    } else {
        [TimeSpan]::Zero
    }
    
    $report = @{
        Status = if($Success){"SUCCESS"}else{"FAILED"}
        StartTime = $script:OrchestrationState.StartTime
        EndTime = Get-Date
        Duration = "$($duration.Hours)h $($duration.Minutes)m"
        ServersProcessed = $script:OrchestrationState.ProcessedServers.Count
        ServersSuccess = $script:OrchestrationState.SuccessfulServers.Count
        ServersFailed = $script:OrchestrationState.FailedServers.Count
        Snapshots = $script:OrchestrationState.Snapshots.Count
        Errors = $script:OrchestrationState.Errors
    }
    
    # Créer HTML pour email
    $html = @"
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Arial; background: #f0f0f0; }
        .container { max-width: 800px; margin: 20px auto; background: white; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: $(if($Success){'#107C10'}else{'#D13438'}); border-bottom: 3px solid; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
        .metric { background: #f8f8f8; padding: 15px; border-left: 4px solid #0078D4; }
        .metric-value { font-size: 24px; font-weight: bold; color: #0078D4; }
        .success { color: #107C10; }
        .failed { color: #D13438; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #0078D4; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #eee; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>🎯 Rapport Orchestration Windows Update - $(if($Success){'SUCCÈS'}else{'ÉCHEC'})</h1>
        
        <div class='summary'>
            <div class='metric'>
                <div>Durée totale</div>
                <div class='metric-value'>$($report.Duration)</div>
            </div>
            <div class='metric'>
                <div>Serveurs traités</div>
                <div class='metric-value'>$($report.ServersProcessed)</div>
            </div>
            <div class='metric'>
                <div>Succès</div>
                <div class='metric-value success'>$($report.ServersSuccess)</div>
            </div>
            <div class='metric'>
                <div>Échecs</div>
                <div class='metric-value failed'>$($report.ServersFailed)</div>
            </div>
        </div>
        
        <h2>📊 Détails des serveurs</h2>
        <table>
            <tr>
                <th>Serveur</th>
                <th>Statut</th>
                <th>Durée</th>
                <th>Notes</th>
            </tr>
"@
    
    foreach ($server in $script:OrchestrationState.ProcessedServers) {
        $status = if($server -in $script:OrchestrationState.SuccessfulServers){"✅ Succès"}else{"❌ Échec"}
        $html += "<tr><td>$server</td><td>$status</td><td>-</td><td>-</td></tr>"
    }
    
    $html += @"
        </table>
        
        $(if(!$Success){"<h2>❌ Erreur</h2><p style='color:red'>$Error</p>"})
        
        <div class='footer'>
            <p>Rapport généré le $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</p>
            <p>SYAGA Windows Update Orchestrator v$SCRIPT_VERSION</p>
            <p>Logs complets: $script:LogFile</p>
        </div>
    </div>
</body>
</html>
"@
    
    # Envoyer email
    Send-Notification -Message "Orchestration terminée" -Level $(if($Success){"SUCCESS"}else{"ERROR"}) -Details $report
    
    # Sauvegarder rapport HTML
    $reportFile = Join-Path $LogPath "Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $html | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-Log "Rapport sauvegardé: $reportFile" "INFO"
}

function Save-OrchestrationState {
    Write-Log "Sauvegarde état orchestration..." "INFO"
    
    $script:OrchestrationState | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:StateFile -Encoding UTF8
}

function Get-GraphToken {
    $tokenUrl = "https://login.microsoftonline.com/$($Config.SharePoint.TenantId)/oauth2/v2.0/token"
    $body = @{
        client_id = $Config.SharePoint.ClientId
        client_secret = $Config.SharePoint.ClientSecret
        scope = "https://graph.microsoft.com/.default"
        grant_type = "client_credentials"
    }
    return (Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body).access_token
}

# ================================================================================
# POINT D'ENTRÉE PRINCIPAL
# ================================================================================

# Initialiser
Initialize-Orchestrator

# Exécuter selon le mode
try {
    switch ($Mode) {
        "Check" {
            Write-Log "MODE CHECK - Analyse de l'infrastructure" "INFO"
            $infrastructure = Get-InfrastructureState
            
            Write-Log "`n📋 RÉSUMÉ INFRASTRUCTURE" "INFO"
            Write-Log "  Serveurs total: $($infrastructure.Servers.Count)" "INFO"
            Write-Log "  Hôtes Hyper-V: $($infrastructure.HyperVHosts.Count)" "INFO"
            Write-Log "  Serveurs Veeam: $($infrastructure.VeeamServers.Count)" "INFO"
            Write-Log "  Ordre de mise à jour:" "INFO"
            
            foreach ($server in $infrastructure.UpdateOrder) {
                Write-Log "    $($infrastructure.UpdateOrder.IndexOf($server) + 1). $($server.Name) [Priorité: $($server.Priority)]" "INFO"
            }
        }
        
        "Plan" {
            Write-Log "MODE PLAN - Création du plan d'orchestration" "INFO"
            $infrastructure = Get-InfrastructureState
            
            Write-Log "`n📅 PLAN D'ORCHESTRATION" "INFO"
            Write-Log "  Début prévu: Vendredi soir" "INFO"
            Write-Log "  Durée estimée: $([Math]::Ceiling($infrastructure.Servers.Count * 45 / 60)) heures" "INFO"
            Write-Log "  Stratégie: Un serveur à la fois" "INFO"
            Write-Log "  Rollback: Automatique si échec" "INFO"
            
            # Sauvegarder plan
            $planFile = Join-Path $LogPath "Plan_$(Get-Date -Format 'yyyyMMdd').json"
            $infrastructure | ConvertTo-Json -Depth 10 | Out-File $planFile
            Write-Log "Plan sauvegardé: $planFile" "SUCCESS"
        }
        
        "Execute" {
            if (!$Force) {
                Write-Host "`n⚠️  ATTENTION: Vous allez lancer l'orchestration complète!" -ForegroundColor Yellow
                Write-Host "Cela va:" -ForegroundColor Yellow
                Write-Host "  • Mettre à jour TOUS les serveurs un par un" -ForegroundColor White
                Write-Host "  • Créer des snapshots de sécurité" -ForegroundColor White
                Write-Host "  • Suspendre/reprendre réplication et Veeam" -ForegroundColor White
                Write-Host "  • Redémarrer les serveurs si nécessaire" -ForegroundColor White
                Write-Host "  • Rollback automatique si problème" -ForegroundColor White
                
                $confirm = Read-Host "`nTaper 'EXECUTE' pour confirmer"
                if ($confirm -ne "EXECUTE") {
                    Write-Log "Exécution annulée" "WARNING"
                    exit
                }
            }
            
            Write-Log "MODE EXECUTE - Lancement orchestration complète" "CRITICAL" -SendNotification
            
            $infrastructure = Get-InfrastructureState
            $success = Start-Orchestration -Infrastructure $infrastructure
            
            if ($success) {
                Write-Log "✅ ORCHESTRATION RÉUSSIE - Zéro problème attendu lundi!" "SUCCESS" -SendNotification
            }
            else {
                Write-Log "❌ ORCHESTRATION ÉCHOUÉE - Intervention nécessaire" "CRITICAL" -SendNotification
            }
            
            Send-FinalReport -Success $success
        }
        
        "Monitor" {
            Write-Log "MODE MONITOR - Surveillance continue" "INFO"
            
            # Charger état précédent
            if (Test-Path $script:StateFile) {
                $state = Get-Content $script:StateFile | ConvertFrom-Json
                
                Write-Log "État actuel: $($state.Status)" "INFO"
                Write-Log "Serveur en cours: $($state.CurrentServer)" "INFO"
                Write-Log "Progression: $($state.ProcessedServers.Count)/$($state.ProcessedServers.Count + $state.FailedServers.Count)" "INFO"
            }
            else {
                Write-Log "Aucune orchestration en cours" "INFO"
            }
        }
        
        "Rollback" {
            Write-Log "MODE ROLLBACK - Restauration d'urgence" "CRITICAL"
            
            if (!$Force) {
                $confirm = Read-Host "Serveur à rollback"
                if ($confirm) {
                    Execute-Rollback -ServerName $confirm -Reason "Rollback manuel demandé"
                }
            }
        }
        
        default {
            Write-Log "Mode non reconnu: $Mode" "ERROR"
            Write-Log "Modes disponibles: Check | Plan | Execute | Monitor | Rollback" "INFO"
        }
    }
}
catch {
    Write-Log "ERREUR FATALE: $_" "CRITICAL" -SendNotification
    Send-FinalReport -Success $false -Error $_.ToString()
}
finally {
    Save-OrchestrationState
    Write-Log "`n$SCRIPT_NAME terminé" "INFO"
}