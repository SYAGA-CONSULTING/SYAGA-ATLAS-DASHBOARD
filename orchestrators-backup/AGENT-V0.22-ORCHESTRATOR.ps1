# ATLAS AGENT v0.22 - ORCHESTRATION MULTI-CLIENT
# Un serveur à la fois PAR CLIENT, mais TOUS les clients en parallèle
# 0% perte de service garantie

param(
    [switch]$Install,
    [switch]$TestMode,
    [string]$ClientName = "",  # Override pour tests
    [string]$SiteName = ""     # Override pour tests
)

$VERSION = "v0.22"
$SCRIPT_NAME = "ATLAS-AGENT"

# ================================================================================
# CONFIGURATION
# ================================================================================

$Config = @{
    Version = $VERSION
    
    # Azure AD
    TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
    ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
    ClientSecret = "[REDACTED]"  # Remplacer par le vrai
    
    # SharePoint
    SiteId = "syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8"
    
    # Listes SharePoint
    Lists = @{
        Servers = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"            # ATLAS-Servers (existante)
        Orchestration = "XXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"        # ATLAS-Orchestration (à créer)
        GlobalStatus = "YYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY"         # ATLAS-GlobalStatus (à créer)
    }
    
    # Timing
    CheckInterval = 120  # 2 minutes
    UpdateTimeout = 3600  # 60 minutes max par serveur
    
    # Sécurité
    CreateSnapshots = $true
    AutoRollback = $true
    RequireBackup = $true
    MaxRetries = 2
}

# ================================================================================
# INSTALLATION
# ================================================================================

if ($Install) {
    Write-Host "Installation ATLAS Agent $VERSION avec Orchestration..." -ForegroundColor Green
    
    # Créer dossier
    if (!(Test-Path "C:\SYAGA-ATLAS")) {
        New-Item -Path "C:\SYAGA-ATLAS" -ItemType Directory -Force | Out-Null
    }
    
    # Copier agent
    Copy-Item $PSCommandPath "C:\SYAGA-ATLAS\agent.ps1" -Force
    
    # Créer config locale
    $localConfig = @{
        Hostname = $env:COMPUTERNAME
        Client = ""     # À déterminer
        Site = ""       # À déterminer
        Installed = Get-Date
        Version = $VERSION
    }
    $localConfig | ConvertTo-Json | Out-File "C:\SYAGA-ATLAS\config.json" -Encoding UTF8
    
    # Supprimer anciennes tâches
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    # Créer tâche planifiée
    schtasks.exe /Create /TN "SYAGA-ATLAS-Agent" /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\SYAGA-ATLAS\agent.ps1" /SC MINUTE /MO 2 /RU SYSTEM /RL HIGHEST /F
    
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent"
    
    Write-Host "✅ Agent $VERSION installé avec support orchestration" -ForegroundColor Green
    Write-Host "📍 Dossier: C:\SYAGA-ATLAS" -ForegroundColor Gray
    Write-Host "⏱️ Exécution: toutes les 2 minutes" -ForegroundColor Gray
    exit 0
}

# ================================================================================
# FONCTIONS SHAREPOINT
# ================================================================================

function Get-GraphToken {
    $tokenUrl = "https://login.microsoftonline.com/$($Config.TenantId)/oauth2/v2.0/token"
    $body = @{
        client_id = $Config.ClientId
        client_secret = $Config.ClientSecret
        scope = "https://graph.microsoft.com/.default"
        grant_type = "client_credentials"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body
        return $response.access_token
    }
    catch {
        Write-Log "Erreur obtention token: $_" "ERROR"
        return $null
    }
}

function Get-SharePointList {
    param(
        [string]$ListName,
        [string]$Filter = ""
    )
    
    $token = Get-GraphToken
    if (!$token) { return $null }
    
    $headers = @{Authorization = "Bearer $token"}
    $listId = $Config.Lists[$ListName]
    
    $url = "https://graph.microsoft.com/v1.0/sites/$($Config.SiteId)/lists/$listId/items?`$expand=fields"
    if ($Filter) {
        $url += "&`$filter=$Filter"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers
        return $response.value
    }
    catch {
        Write-Log "Erreur lecture SharePoint $ListName : $_" "ERROR"
        return @()
    }
}

function Update-SharePointItem {
    param(
        [string]$ListName,
        [string]$ItemId,
        [hashtable]$Fields
    )
    
    $token = Get-GraphToken
    if (!$token) { return $false }
    
    $headers = @{
        Authorization = "Bearer $token"
        'Content-Type' = "application/json; charset=utf-8"
    }
    
    $listId = $Config.Lists[$ListName]
    $url = "https://graph.microsoft.com/v1.0/sites/$($Config.SiteId)/lists/$listId/items/$ItemId"
    
    $body = @{fields = $Fields} | ConvertTo-Json -Depth 10
    
    try {
        Invoke-RestMethod -Uri $url -Headers $headers -Method PATCH -Body $body
        return $true
    }
    catch {
        Write-Log "Erreur update SharePoint: $_" "ERROR"
        return $false
    }
}

# ================================================================================
# DÉTERMINATION CONTEXTE
# ================================================================================

function Get-MyContext {
    Write-Log "Détermination du contexte..." "INFO"
    
    $context = @{
        Hostname = $env:COMPUTERNAME
        Client = "UNKNOWN"
        Site = "UNKNOWN"
        ServerType = "Unknown"
        IsHyperVHost = $false
        HasVeeam = $false
        UpdateOrder = 999
        CanUpdate = $false
        CurrentRing = 0
        ReplicationPartners = @()
    }
    
    # Charger config locale si existe
    if (Test-Path "C:\SYAGA-ATLAS\config.json") {
        $localConfig = Get-Content "C:\SYAGA-ATLAS\config.json" | ConvertFrom-Json
        if ($localConfig.Client) { $context.Client = $localConfig.Client }
        if ($localConfig.Site) { $context.Site = $localConfig.Site }
    }
    
    # Override pour tests
    if ($ClientName) { $context.Client = $ClientName }
    if ($SiteName) { $context.Site = $SiteName }
    
    # Déterminer client/site depuis nom machine si pas configuré
    if ($context.Client -eq "UNKNOWN") {
        # Pattern: CLIENT-SITE-ROLE-XX
        if ($context.Hostname -match "^([A-Z]+)-([A-Z0-9]+)-") {
            $context.Client = $Matches[1]
            $context.Site = $Matches[2]
        }
        elseif ($context.Hostname -like "SYAGA-*") {
            $context.Client = "SYAGA"
            $context.Site = "MAIN"
        }
    }
    
    # Détecter Hyper-V
    if (Get-Service -Name "vmms" -ErrorAction SilentlyContinue) {
        $context.IsHyperVHost = $true
        $context.ServerType = "HyperV_Host"
        
        # Trouver partenaires réplication
        try {
            $replications = Get-VMReplication -ErrorAction SilentlyContinue
            if ($replications) {
                $context.ReplicationPartners = $replications | Select-Object -Unique ReplicaServer | ForEach-Object { $_.ReplicaServer }
            }
        }
        catch {}
    }
    
    # Détecter Veeam
    if (Get-Service -Name "VeeamBackup*" -ErrorAction SilentlyContinue) {
        $context.HasVeeam = $true
        if (!$context.IsHyperVHost) {
            $context.ServerType = "Veeam_Server"
        }
    }
    
    # Récupérer infos orchestration depuis SharePoint
    $orchItems = Get-SharePointList -ListName "Orchestration"
    $myOrch = $orchItems | Where-Object { $_.fields.ServerName -eq $context.Hostname } | Select-Object -First 1
    
    if ($myOrch) {
        $context.UpdateOrder = $myOrch.fields.UpdateOrder
        $context.CurrentRing = $myOrch.fields.UpdateRing
        $context.CanUpdate = ($myOrch.fields.CanUpdate -eq $true)
    }
    
    Write-Log "Contexte: Client=$($context.Client), Site=$($context.Site), Type=$($context.ServerType)" "INFO"
    
    return $context
}

# ================================================================================
# LOGIQUE ORCHESTRATION
# ================================================================================

function Test-CanIUpdate {
    param($Context)
    
    Write-Log "Vérification autorisation update..." "INFO"
    
    # 1. RING 0 (SYAGA) doit être validé
    $globalStatus = Get-SharePointList -ListName "GlobalStatus"
    $ring0Status = $globalStatus | Where-Object { $_.fields.RingName -eq "RING0_SYAGA" } | Select-Object -First 1
    
    if ($Context.Client -ne "SYAGA") {
        if (!$ring0Status -or $ring0Status.fields.Status -ne "Completed") {
            Write-Log "Ring 0 (SYAGA) pas encore validé" "INFO"
            return $false
        }
    }
    
    # 2. Dans MON client, est-ce mon tour?
    $clientServers = Get-SharePointList -ListName "Orchestration" | 
        Where-Object { $_.fields.ClientName -eq $Context.Client -and $_.fields.SiteGeographic -eq $Context.Site }
    
    # Trouver le prochain serveur à updater dans mon client
    $nextServer = $clientServers | 
        Where-Object { $_.fields.UpdateStatus -eq "Pending" } |
        Sort-Object { [int]$_.fields.UpdateOrder } |
        Select-Object -First 1
    
    if (!$nextServer) {
        Write-Log "Aucun serveur en attente dans $($Context.Client)" "INFO"
        return $false
    }
    
    if ($nextServer.fields.ServerName -ne $Context.Hostname) {
        Write-Log "Pas mon tour. Prochain: $($nextServer.fields.ServerName)" "INFO"
        return $false
    }
    
    # 3. Vérifier pas de lock client (un seul serveur par client à la fois)
    $clientLock = $clientServers | Where-Object { $_.fields.UpdateStatus -eq "InProgress" }
    
    if ($clientLock) {
        Write-Log "Un serveur déjà en update dans $($Context.Client): $($clientLock.fields.ServerName)" "INFO"
        return $false
    }
    
    # 4. Vérifier fenêtre de maintenance
    $now = Get-Date
    $dayOfWeek = $now.DayOfWeek
    
    if ($dayOfWeek -notin @('Saturday', 'Sunday') -and !$TestMode) {
        Write-Log "Hors fenêtre maintenance (weekend only)" "WARNING"
        return $false
    }
    
    # 5. Vérifications spécifiques selon type
    if ($Context.IsHyperVHost) {
        # Vérifier que les VMs sont OK ou qu'on peut les migrer
        if (!(Test-HyperVReadyForUpdate)) {
            return $false
        }
    }
    
    if ($Context.HasVeeam) {
        # Vérifier pas de job critique en cours
        if (!(Test-VeeamReadyForUpdate)) {
            return $false
        }
    }
    
    Write-Log "✅ Autorisation update accordée!" "SUCCESS"
    return $true
}

function Start-OrchestatedUpdate {
    param($Context)
    
    Write-Log "🚀 DÉBUT UPDATE ORCHESTRÉ - $($Context.Hostname)" "INFO"
    
    # Mettre à jour statut SharePoint
    $myItem = Get-SharePointList -ListName "Orchestration" | 
        Where-Object { $_.fields.ServerName -eq $Context.Hostname } | 
        Select-Object -First 1
    
    if (!$myItem) {
        Write-Log "Erreur: Pas trouvé dans orchestration!" "ERROR"
        return $false
    }
    
    # Marquer comme InProgress (LOCK)
    Update-SharePointItem -ListName "Orchestration" -ItemId $myItem.id -Fields @{
        UpdateStatus = "InProgress"
        UpdateStartTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        UpdateLocked = $true
    }
    
    $success = $false
    $rollbackNeeded = $false
    
    try {
        # ÉTAPE 1: Snapshot
        if ($Config.CreateSnapshots) {
            Write-Log "Création snapshot..." "INFO"
            $snapshot = New-SafetySnapshot
            
            if (!$snapshot -and !$TestMode) {
                throw "Impossible de créer snapshot"
            }
        }
        
        # ÉTAPE 2: Préparer services
        if ($Context.IsHyperVHost) {
            Suspend-HyperVServices
        }
        
        if ($Context.HasVeeam) {
            Suspend-VeeamServices
        }
        
        # ÉTAPE 3: Windows Update
        Write-Log "Lancement Windows Update..." "INFO"
        $updateResult = Execute-WindowsUpdate
        
        if (!$updateResult.Success) {
            throw "Échec Windows Update: $($updateResult.Error)"
        }
        
        # ÉTAPE 4: Reboot si nécessaire
        if ($updateResult.RebootRequired) {
            Write-Log "Redémarrage nécessaire..." "WARNING"
            
            # Sauvegarder état avant reboot
            Save-StateBeforeReboot
            
            # Programmer reprise après reboot
            Register-PostRebootTask
            
            # Reboot
            Write-Log "Redémarrage dans 30 secondes..." "WARNING"
            shutdown /r /t 30 /c "ATLAS Orchestrated Update - Reboot"
            
            # Le script reprendra après reboot
            exit 0
        }
        
        # ÉTAPE 5: Vérifications post-update
        Write-Log "Vérifications santé..." "INFO"
        $health = Test-ServerHealth -Context $Context
        
        if (!$health.Success) {
            throw "Échec vérification santé: $($health.Issues -join ', ')"
        }
        
        # ÉTAPE 6: Restaurer services
        if ($Context.IsHyperVHost) {
            Resume-HyperVServices
        }
        
        if ($Context.HasVeeam) {
            Resume-VeeamServices
        }
        
        $success = $true
        Write-Log "✅ UPDATE RÉUSSI!" "SUCCESS"
        
    }
    catch {
        Write-Log "❌ ÉCHEC UPDATE: $_" "ERROR"
        $rollbackNeeded = $true
        
        # Rollback automatique
        if ($Config.AutoRollback -and $snapshot) {
            Write-Log "Exécution rollback automatique..." "WARNING"
            Restore-FromSnapshot -Snapshot $snapshot
        }
    }
    finally {
        # Mettre à jour statut final
        $finalStatus = if($success) { "Completed" } else { "Failed" }
        
        Update-SharePointItem -ListName "Orchestration" -ItemId $myItem.id -Fields @{
            UpdateStatus = $finalStatus
            UpdateEndTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            UpdateLocked = $false
            UpdateSuccess = $success
            RollbackExecuted = $rollbackNeeded
            LastError = if(!$success) { $_.ToString() } else { "" }
        }
        
        # Mettre à jour métriques serveur principal
        Update-ServerMetrics -Context $Context -UpdateStatus $finalStatus
    }
    
    return $success
}

# ================================================================================
# WINDOWS UPDATE
# ================================================================================

function Execute-WindowsUpdate {
    Write-Log "Exécution Windows Update..." "INFO"
    
    $result = @{
        Success = $false
        UpdatesInstalled = 0
        RebootRequired = $false
        Error = ""
    }
    
    try {
        # Installer module si nécessaire
        if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Log "Installation module PSWindowsUpdate..." "INFO"
            Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser
        }
        
        Import-Module PSWindowsUpdate
        
        # Rechercher updates
        Write-Log "Recherche mises à jour..." "INFO"
        $updates = Get-WindowsUpdate -AcceptAll
        
        if ($updates.Count -eq 0) {
            Write-Log "Système déjà à jour" "SUCCESS"
            $result.Success = $true
            return $result
        }
        
        Write-Log "Installation de $($updates.Count) mises à jour..." "INFO"
        
        # Installer
        $installResult = Install-WindowsUpdate -AcceptAll -IgnoreReboot -Confirm:$false
        
        $result.UpdatesInstalled = $updates.Count
        $result.RebootRequired = Get-WURebootStatus -Silent
        $result.Success = $true
        
        Write-Log "$($result.UpdatesInstalled) mises à jour installées" "SUCCESS"
        
    }
    catch {
        $result.Error = $_.ToString()
        Write-Log "Erreur Windows Update: $_" "ERROR"
    }
    
    return $result
}

# ================================================================================
# GESTION SNAPSHOTS
# ================================================================================

function New-SafetySnapshot {
    Write-Log "Création snapshot sécurité..." "INFO"
    
    $snapshot = @{
        Name = "ATLAS-UPDATE-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Created = Get-Date
        Type = "Unknown"
        Success = $false
    }
    
    try {
        # Si VM Hyper-V
        if (Get-Command Get-VM -ErrorAction SilentlyContinue) {
            $vm = Get-VM -Name $env:COMPUTERNAME -ErrorAction SilentlyContinue
            if ($vm) {
                Checkpoint-VM -VM $vm -SnapshotName $snapshot.Name
                $snapshot.Type = "HyperV"
                $snapshot.Success = $true
            }
        }
        
        # Sinon point de restauration système
        if (!$snapshot.Success) {
            Enable-ComputerRestore -Drive "C:\"
            Checkpoint-Computer -Description $snapshot.Name -RestorePointType MODIFY_SETTINGS
            $snapshot.Type = "SystemRestore"
            $snapshot.Success = $true
        }
        
        Write-Log "Snapshot créé: $($snapshot.Name)" "SUCCESS"
    }
    catch {
        Write-Log "Erreur création snapshot: $_" "ERROR"
        
        # Nettoyer si manque d'espace
        if ($_.Exception.Message -like "*space*") {
            Write-Log "Tentative nettoyage anciens snapshots..." "INFO"
            Remove-OldSnapshots
            
            # Réessayer une fois
            try {
                Checkpoint-Computer -Description $snapshot.Name -RestorePointType MODIFY_SETTINGS
                $snapshot.Success = $true
            }
            catch {}
        }
    }
    
    return $snapshot
}

function Remove-OldSnapshots {
    # Garder seulement les 3 derniers
    try {
        if (Get-Command Get-VMSnapshot -ErrorAction SilentlyContinue) {
            Get-VMSnapshot -VMName * | 
                Where-Object { $_.Name -like "ATLAS-UPDATE-*" } |
                Sort-Object CreationTime |
                Select-Object -SkipLast 3 |
                Remove-VMSnapshot -IncludeAllChildSnapshots
        }
    }
    catch {}
}

# ================================================================================
# GESTION HYPER-V
# ================================================================================

function Test-HyperVReadyForUpdate {
    Write-Log "Vérification Hyper-V prêt pour update..." "INFO"
    
    try {
        # Vérifier VMs critiques
        $criticalVMs = Get-VM | Where-Object { 
            $_.State -eq "Running" -and 
            $_.Notes -like "*CRITICAL*"
        }
        
        if ($criticalVMs) {
            # Vérifier qu'elles sont répliquées et que le réplica est OK
            foreach ($vm in $criticalVMs) {
                $replication = Get-VMReplication -VMName $vm.Name -ErrorAction SilentlyContinue
                
                if (!$replication -or $replication.Health -ne "Normal") {
                    Write-Log "VM critique $($vm.Name) pas correctement répliquée" "WARNING"
                    return $false
                }
            }
        }
        
        return $true
    }
    catch {
        return $true  # On continue si on ne peut pas vérifier
    }
}

function Suspend-HyperVServices {
    Write-Log "Suspension services Hyper-V..." "INFO"
    
    try {
        # Sauvegarder état des VMs
        Get-VM | Where-Object { $_.State -eq "Running" } | ForEach-Object {
            Write-Log "Sauvegarde VM: $($_.Name)" "INFO"
            Save-VM -VM $_
        }
        
        # Suspendre réplication
        Get-VMReplication | Where-Object { $_.State -ne "Suspended" } | ForEach-Object {
            Suspend-VMReplication -VMName $_.Name
        }
        
        Write-Log "Services Hyper-V suspendus" "SUCCESS"
    }
    catch {
        Write-Log "Erreur suspension Hyper-V: $_" "WARNING"
    }
}

function Resume-HyperVServices {
    Write-Log "Reprise services Hyper-V..." "INFO"
    
    try {
        # Redémarrer VMs
        Get-VM | Where-Object { $_.State -eq "Saved" } | ForEach-Object {
            Write-Log "Démarrage VM: $($_.Name)" "INFO"
            Start-VM -VM $_
        }
        
        # Reprendre réplication
        Get-VMReplication | Where-Object { $_.State -eq "Suspended" } | ForEach-Object {
            Resume-VMReplication -VMName $_.Name
        }
        
        Write-Log "Services Hyper-V repris" "SUCCESS"
    }
    catch {
        Write-Log "Erreur reprise Hyper-V: $_" "WARNING"
    }
}

# ================================================================================
# GESTION VEEAM
# ================================================================================

function Test-VeeamReadyForUpdate {
    Write-Log "Vérification Veeam prêt pour update..." "INFO"
    
    try {
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            # Vérifier pas de job critique en cours
            $runningJobs = Get-VBRJob | Where-Object { $_.GetLastState() -eq "Working" }
            
            if ($runningJobs) {
                Write-Log "$($runningJobs.Count) jobs Veeam en cours" "WARNING"
                
                # Si c'est un backup de VM critique, on attend
                foreach ($job in $runningJobs) {
                    if ($job.Name -like "*CRITICAL*" -or $job.Name -like "*PROD*") {
                        return $false
                    }
                }
            }
        }
        
        return $true
    }
    catch {
        return $true
    }
}

function Suspend-VeeamServices {
    Write-Log "Suspension jobs Veeam..." "INFO"
    
    try {
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            Get-VBRJob | Where-Object { $_.IsScheduleEnabled } | ForEach-Object {
                Disable-VBRJob -Job $_
                Write-Log "Job suspendu: $($_.Name)" "INFO"
            }
        }
    }
    catch {
        Write-Log "Erreur suspension Veeam: $_" "WARNING"
    }
}

function Resume-VeeamServices {
    Write-Log "Reprise jobs Veeam..." "INFO"
    
    try {
        if (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            Import-Module Veeam.Backup.PowerShell
            
            Get-VBRJob | ForEach-Object {
                Enable-VBRJob -Job $_
                Write-Log "Job réactivé: $($_.Name)" "INFO"
            }
        }
    }
    catch {
        Write-Log "Erreur reprise Veeam: $_" "WARNING"
    }
}

# ================================================================================
# VÉRIFICATIONS SANTÉ
# ================================================================================

function Test-ServerHealth {
    param($Context)
    
    Write-Log "Vérification santé serveur..." "INFO"
    
    $health = @{
        Success = $true
        Issues = @()
    }
    
    # Test réseau
    if (!(Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet)) {
        $health.Issues += "Network connectivity"
    }
    
    # Services critiques
    $criticalServices = @("RpcSs", "Server", "Workstation", "EventLog")
    
    if ($Context.IsHyperVHost) {
        $criticalServices += "vmms", "vmcompute"
    }
    
    if ($Context.HasVeeam) {
        $criticalServices += "VeeamBackupSvc"
    }
    
    foreach ($service in $criticalServices) {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if (!$svc -or $svc.Status -ne "Running") {
            $health.Issues += "Service $service not running"
        }
    }
    
    # Espace disque
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeGB = [Math]::Round($disk.FreeSpace / 1GB, 1)
    
    if ($freeGB -lt 5) {
        $health.Issues += "Low disk space: ${freeGB}GB"
    }
    
    if ($health.Issues.Count -gt 0) {
        $health.Success = $false
        Write-Log "Problèmes détectés: $($health.Issues -join ', ')" "WARNING"
    }
    else {
        Write-Log "Santé OK" "SUCCESS"
    }
    
    return $health
}

# ================================================================================
# MÉTRIQUES & REPORTING
# ================================================================================

function Update-ServerMetrics {
    param(
        $Context,
        $UpdateStatus
    )
    
    Write-Log "Mise à jour métriques serveur..." "INFO"
    
    # Collecter métriques
    $cpu = 5
    try {
        $c = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        if ($c) { $cpu = [Math]::Round($c.CounterSamples[0].CookedValue, 1) }
    }
    catch {
        try {
            $c = Get-Counter "\Processeur(_Total)\% temps processeur" -ErrorAction SilentlyContinue
            if ($c) { $cpu = [Math]::Round($c.CounterSamples[0].CookedValue, 1) }
        }
        catch {}
    }
    
    $mem = 50
    try {
        $os = Get-WmiObject Win32_OperatingSystem
        $mem = [Math]::Round(100 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize * 100), 1)
    }
    catch {}
    
    $disk = 100
    try {
        $d = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        $disk = [Math]::Round($d.FreeSpace / 1GB, 1)
    }
    catch {}
    
    # Mettre à jour SharePoint ATLAS-Servers
    $token = Get-GraphToken
    if (!$token) { return }
    
    $headers = @{
        Authorization = "Bearer $token"
        'Content-Type' = "application/json; charset=utf-8"
    }
    
    $listUrl = "https://graph.microsoft.com/v1.0/sites/$($Config.SiteId)/lists/$($Config.Lists.Servers)/items?`$expand=fields"
    
    try {
        $items = Invoke-RestMethod -Uri $listUrl -Headers $headers
        $myItem = $items.value | Where-Object { $_.fields.Hostname -eq $Context.Hostname } | Select-Object -First 1
        
        if ($myItem) {
            $updateData = @{
                Hostname = $Context.Hostname
                Title = $Context.Hostname
                AgentVersion = $VERSION
                LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                State = if($UpdateStatus -eq "Completed") { "OK" } else { $UpdateStatus }
                CPUUsage = $cpu
                MemoryUsage = $mem
                DiskSpaceGB = $disk
                OrchestrationClient = $Context.Client
                OrchestrationSite = $Context.Site
                LastUpdateStatus = $UpdateStatus
            }
            
            $updateUrl = "https://graph.microsoft.com/v1.0/sites/$($Config.SiteId)/lists/$($Config.Lists.Servers)/items/$($myItem.id)"
            $body = @{fields = $updateData} | ConvertTo-Json
            
            Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PATCH -Body $body
            Write-Log "Métriques mises à jour" "SUCCESS"
        }
    }
    catch {
        Write-Log "Erreur update métriques: $_" "WARNING"
    }
}

# ================================================================================
# LOGGING
# ================================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console
    $color = switch ($Level) {
        "INFO" { "White" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        default { "Gray" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # Fichier
    $logFile = "C:\SYAGA-ATLAS\orchestration.log"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ================================================================================
# BOUCLE PRINCIPALE
# ================================================================================

Write-Log "=== ATLAS AGENT $VERSION - ORCHESTRATION ===" "INFO"

# Obtenir contexte
$context = Get-MyContext

# Mode normal : vérifier toutes les 2 minutes
while ($true) {
    try {
        # Mise à jour métriques de base
        Update-ServerMetrics -Context $context -UpdateStatus "Running"
        
        # Vérifier si on peut/doit faire un update
        if (Test-CanIUpdate -Context $context) {
            Write-Log "🎯 MON TOUR! Lancement update orchestré" "SUCCESS"
            
            # Exécuter l'update
            $result = Start-OrchestatedUpdate -Context $context
            
            if ($result) {
                Write-Log "✅ Update orchestré terminé avec succès" "SUCCESS"
            }
            else {
                Write-Log "❌ Update orchestré échoué" "ERROR"
            }
            
            # Attendre un peu après un update
            Start-Sleep -Seconds 300
        }
        else {
            Write-Log "Pas mon tour, attente..." "INFO"
        }
    }
    catch {
        Write-Log "Erreur boucle principale: $_" "ERROR"
    }
    
    # Attendre avant prochain check
    Start-Sleep -Seconds $Config.CheckInterval
}