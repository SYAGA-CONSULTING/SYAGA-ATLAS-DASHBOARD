# ATLAS Agent v5.5 AUTOUPDATE - Avec mise à jour automatique
# Services, Events, Veeam, Certificats, Hyper-V, Replication + Auto-update

param(
    [string]$Action = "Executer",
    [int]$IntervalleMinutes = 3
)

# Configuration
$Script:Version = "5.5-AUTOUPDATE"
$Script:CheminBase = "C:\ATLAS"
$Script:CheminAgent = "$Script:CheminBase\Agent"
$Script:CheminLogs = "$Script:CheminBase\Logs"
$Script:FichierLog = "$Script:CheminLogs\Agent-$(Get-Date -Format 'yyyyMMdd').log"
$Script:FichierAgentActuel = "$Script:CheminAgent\ATLAS-Agent-Current.ps1"
$Script:NomTache = "ATLAS-Agent-v5"

# SharePoint
$Script:TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$Script:ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
$Script:ClientSecret = "" # Sera lu depuis le fichier de config
$Script:SiteUrl = "https://syagaconsulting.sharepoint.com/sites/SYAGA-Atlas"
$Script:ConfigFile = "$Script:CheminBase\config.json"

# Services critiques a monitorer
$Script:ServicesCritiques = @(
    "W3SVC",        # IIS
    "MSSQLSERVER",  # SQL Server
    "VeeamBackupSvc", # Veeam Backup
    "vmms",         # Hyper-V
    "vmcompute",    # Hyper-V Compute
    "WinRM",        # Windows Remote Management
    "EventLog"      # Event Log
)

function Ecrire-Log {
    param(
        [string]$Message,
        [string]$Niveau = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Niveau] [v$Script:Version] $Message"
    
    $couleur = switch ($Niveau) {
        "ERREUR" { "Red" }
        "SUCCES" { "Green" }
        "AVERTISSEMENT" { "Yellow" }
        "UPDATE" { "Cyan" }
        "DEBUG" { "Gray" }
        default { "White" }
    }
    Write-Host $logEntry -ForegroundColor $couleur
    
    try {
        if (Test-Path $Script:CheminLogs) {
            Add-Content -Path $Script:FichierLog -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }
    catch {}
}

function Creer-Repertoires {
    $success = $true
    @($Script:CheminBase, $Script:CheminAgent, $Script:CheminLogs) | ForEach-Object {
        $rep = $_
        if (!(Test-Path $rep)) {
            try {
                New-Item -ItemType Directory -Path $rep -Force -ErrorAction Stop | Out-Null
                Ecrire-Log "  Repertoire cree: $rep" "SUCCES"
            }
            catch {
                Ecrire-Log "  ERREUR creation $rep : $_" "ERREUR"
                $success = $false
            }
        }
    }
    return $success
}

function Charger-Configuration {
    # Si le secret n'est pas defini, essayer de le lire depuis la config
    if ([string]::IsNullOrEmpty($Script:ClientSecret)) {
        if (Test-Path $Script:ConfigFile) {
            try {
                $config = Get-Content $Script:ConfigFile -Raw | ConvertFrom-Json
                if ($config.ClientSecret) {
                    $Script:ClientSecret = $config.ClientSecret
                    Ecrire-Log "Configuration chargee depuis $Script:ConfigFile" "DEBUG"
                }
            }
            catch {
                Ecrire-Log "Erreur lecture config: $_" "AVERTISSEMENT"
            }
        }
        else {
            # Créer un fichier de config avec le secret (pour la première installation)
            # Le secret devra être ajouté manuellement ou copié depuis l'ancien agent
            $defaultConfig = @{
                ClientId = $Script:ClientId
                TenantId = $Script:TenantId
                ClientSecret = "REMPLACER_PAR_LE_SECRET"
                SiteUrl = $Script:SiteUrl
            }
            
            $defaultConfig | ConvertTo-Json | Out-File -FilePath $Script:ConfigFile -Encoding UTF8
            Ecrire-Log "Fichier de configuration cree: $Script:ConfigFile" "AVERTISSEMENT"
            Ecrire-Log "IMPORTANT: Ajouter le ClientSecret dans le fichier de configuration!" "ERREUR"
        }
    }
}

function Obtenir-Token {
    try {
        # Charger la configuration si necessaire
        Charger-Configuration
        
        if ([string]::IsNullOrEmpty($Script:ClientSecret) -or $Script:ClientSecret -eq "REMPLACER_PAR_LE_SECRET") {
            Ecrire-Log "ClientSecret non configure dans $Script:ConfigFile" "ERREUR"
            return $null
        }
        
        $body = @{
            client_id = $Script:ClientId
            scope = "https://graph.microsoft.com/.default"
            client_secret = $Script:ClientSecret
            grant_type = "client_credentials"
        }
        
        $tokenUrl = "https://login.microsoftonline.com/$Script:TenantId/oauth2/v2.0/token"
        $response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        return $response.access_token
    }
    catch {
        Ecrire-Log "Erreur obtention token: $_" "ERREUR"
        return $null
    }
}

# ========== FONCTION AUTO-UPDATE ==========
function Verifier-MiseAJour {
    param($Token)
    
    try {
        Ecrire-Log "Verification des mises a jour disponibles..." "UPDATE"
        
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Content-Type" = "application/json"
        }
        
        # Chercher la configuration d'update dans SharePoint
        $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$expand=fields"
        
        $response = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop
        
        # Chercher l'entrée AGENT_CONFIG
        $configItem = $response.value | Where-Object { 
            $_.fields.Title -eq "AGENT_CONFIG" -or 
            $_.fields.Hostname -eq "CONFIG" 
        } | Select-Object -First 1
        
        if ($configItem -and $configItem.fields.State -eq "UPDATE_AVAILABLE") {
            $nouvelleVersion = $configItem.fields.AgentVersion
            
            # Nettoyer les versions pour comparaison
            $currentClean = $Script:Version -replace '^v', ''
            $newClean = $nouvelleVersion -replace '^v', ''
            
            if ($nouvelleVersion -and $newClean -ne $currentClean) {
                Ecrire-Log "NOUVELLE VERSION DISPONIBLE: $nouvelleVersion (actuelle: $Script:Version)" "UPDATE"
                
                # Ne pas downgrader vers une version plus ancienne
                if ($newClean -eq "5.4-ENRICHED" -and $currentClean -eq "5.5-AUTOUPDATE") {
                    Ecrire-Log "Version actuelle plus recente, pas de downgrade" "INFO"
                }
                else {
                    # Télécharger et installer la nouvelle version
                    if (Telecharger-NouvelleVersion -Version $newClean -Token $Token) {
                        Ecrire-Log "Mise a jour reussie vers v$nouvelleVersion" "SUCCES"
                    
                        # Redémarrer avec la nouvelle version
                        Ecrire-Log "Redemarrage avec la nouvelle version..." "UPDATE"
                        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$Script:FichierAgentActuel`" -Action Executer" -NoNewWindow
                        exit 0
                    }
                }
            }
            else {
                Ecrire-Log "Agent deja a jour (v$Script:Version)" "INFO"
            }
        }
        else {
            Ecrire-Log "Pas de mise a jour disponible" "DEBUG"
        }
    }
    catch {
        Ecrire-Log "Erreur verification MAJ: $_" "AVERTISSEMENT"
    }
}

function Telecharger-NouvelleVersion {
    param(
        [string]$Version,
        [string]$Token
    )
    
    try {
        Ecrire-Log "Telechargement de la version $Version..." "UPDATE"
        
        # Nettoyer la version (enlever le v si present)
        $cleanVersion = $Version -replace '^v', ''
        
        # URL du nouveau script sur GitHub
        $githubUrl = "https://raw.githubusercontent.com/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/gh-pages/ATLAS-Agent-v$cleanVersion.ps1"
        
        # Télécharger le nouveau script
        $tempFile = "$env:TEMP\ATLAS-Agent-v$cleanVersion.ps1"
        Invoke-WebRequest -Uri $githubUrl -OutFile $tempFile -ErrorAction Stop
        
        # Vérifier que le fichier a été téléchargé
        if (Test-Path $tempFile) {
            # Copier vers le répertoire agent
            Copy-Item -Path $tempFile -Destination $Script:FichierAgentActuel -Force
            
            # Nettoyer
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            
            Ecrire-Log "Version $Version installee avec succes" "SUCCES"
            return $true
        }
        else {
            throw "Echec telechargement"
        }
    }
    catch {
        Ecrire-Log "Erreur telechargement v$Version : $_" "ERREUR"
        
        # Essayer depuis SharePoint en fallback
        try {
            Ecrire-Log "Tentative alternative depuis SharePoint..." "UPDATE"
            # Ici on pourrait implémenter un téléchargement depuis SharePoint
            return $false
        }
        catch {
            return $false
        }
    }
}

function Obtenir-InfosSysteme {
    $info = @{
        Hostname = $env:COMPUTERNAME
        IPAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        OS = (Get-CimInstance Win32_OperatingSystem).Caption
        Domaine = (Get-CimInstance Win32_ComputerSystem).Domain
    }
    return $info
}

function Obtenir-MetriquesCPU {
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        return @{
            Usage = [Math]::Round($cpu.LoadPercentage, 2)
            Cores = $cpu.NumberOfCores
            LogicalProcessors = $cpu.NumberOfLogicalProcessors
        }
    }
    catch {
        return @{ Usage = 0; Cores = 0; LogicalProcessors = 0 }
    }
}

function Obtenir-MetriquesMemoire {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMem = $os.TotalVisibleMemorySize / 1MB
        $freeMem = $os.FreePhysicalMemory / 1MB
        $usedMem = $totalMem - $freeMem
        $usage = [Math]::Round(($usedMem / $totalMem) * 100, 2)
        
        return @{
            Usage = $usage
            TotalGB = [Math]::Round($totalMem / 1024, 2)
            UsedGB = [Math]::Round($usedMem / 1024, 2)
            FreeGB = [Math]::Round($freeMem / 1024, 2)
        }
    }
    catch {
        return @{ Usage = 0; TotalGB = 0; UsedGB = 0; FreeGB = 0 }
    }
}

function Obtenir-MetriquesDisques {
    try {
        $disques = @()
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $freeGB = [Math]::Round($_.FreeSpace / 1GB, 2)
            $totalGB = [Math]::Round($_.Size / 1GB, 2)
            $usedGB = $totalGB - $freeGB
            $usage = if ($totalGB -gt 0) { [Math]::Round(($usedGB / $totalGB) * 100, 2) } else { 0 }
            
            $disques += @{
                Drive = $_.DeviceID
                FreeGB = $freeGB
                TotalGB = $totalGB
                UsagePercent = $usage
            }
        }
        return $disques
    }
    catch {
        return @()
    }
}

function Obtenir-ServicesWindows {
    try {
        $services = @()
        foreach ($svcName in $Script:ServicesCritiques) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                $services += @{
                    Name = $svc.Name
                    DisplayName = $svc.DisplayName
                    Status = $svc.Status.ToString()
                    StartType = $svc.StartType.ToString()
                }
            }
        }
        return $services
    }
    catch {
        return @()
    }
}

function Obtenir-EvenementsWindows {
    try {
        $events = @{
            Errors24h = (Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddDays(-1) -ErrorAction SilentlyContinue).Count
            Warnings24h = (Get-EventLog -LogName System -EntryType Warning -After (Get-Date).AddDays(-1) -ErrorAction SilentlyContinue).Count
            LastError = ""
        }
        
        $lastError = Get-EventLog -LogName System -EntryType Error -Newest 1 -ErrorAction SilentlyContinue
        if ($lastError) {
            $events.LastError = "$($lastError.TimeGenerated.ToString('yyyy-MM-dd HH:mm:ss')) - $($lastError.Message.Substring(0, [Math]::Min(100, $lastError.Message.Length)))"
        }
        
        return $events
    }
    catch {
        return @{ Errors24h = 0; Warnings24h = 0; LastError = "" }
    }
}

function Obtenir-InfosVeeam {
    try {
        $veeamInfo = @{
            Installed = $false
            ServiceStatus = "N/A"
            LastBackup = "N/A"
            JobsCount = 0
        }
        
        $veeamSvc = Get-Service -Name "VeeamBackupSvc" -ErrorAction SilentlyContinue
        if ($veeamSvc) {
            $veeamInfo.Installed = $true
            $veeamInfo.ServiceStatus = $veeamSvc.Status.ToString()
            
            # Chercher les jobs Veeam (simplifi pour l'exemple)
            $veeamPath = "C:\ProgramData\Veeam\Backup"
            if (Test-Path $veeamPath) {
                $jobFiles = Get-ChildItem -Path $veeamPath -Filter "*.xml" -ErrorAction SilentlyContinue
                $veeamInfo.JobsCount = $jobFiles.Count
            }
        }
        
        return $veeamInfo
    }
    catch {
        return @{ Installed = $false; ServiceStatus = "N/A"; LastBackup = "N/A"; JobsCount = 0 }
    }
}

function Obtenir-InfosCertificats {
    try {
        $certs = @()
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
        $store.Open("ReadOnly")
        
        $store.Certificates | Where-Object { $_.NotAfter -gt (Get-Date) } | ForEach-Object {
            $daysRemaining = ($_.NotAfter - (Get-Date)).Days
            if ($daysRemaining -lt 90) {  # Alerter si expire dans moins de 90 jours
                $certs += @{
                    Subject = $_.Subject
                    Issuer = $_.Issuer
                    ExpirationDate = $_.NotAfter.ToString("yyyy-MM-dd")
                    DaysRemaining = $daysRemaining
                    Alert = ($daysRemaining -lt 30)
                }
            }
        }
        
        $store.Close()
        return $certs
    }
    catch {
        return @()
    }
}

function Obtenir-InfosHyperV {
    try {
        $hyperV = @{
            Installed = $false
            ServiceStatus = "N/A"
            VMCount = 0
            RunningVMs = 0
            VMs = @()
        }
        
        $hyperVFeature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue
        if ($hyperVFeature -and $hyperVFeature.InstallState -eq "Installed") {
            $hyperV.Installed = $true
            
            $vmmsSvc = Get-Service -Name vmms -ErrorAction SilentlyContinue
            if ($vmmsSvc) {
                $hyperV.ServiceStatus = $vmmsSvc.Status.ToString()
            }
            
            $vms = Get-VM -ErrorAction SilentlyContinue
            if ($vms) {
                $hyperV.VMCount = $vms.Count
                $hyperV.RunningVMs = ($vms | Where-Object { $_.State -eq "Running" }).Count
                
                $vms | ForEach-Object {
                    $hyperV.VMs += @{
                        Name = $_.Name
                        State = $_.State.ToString()
                        CPUUsage = $_.CPUUsage
                        MemoryAssigned = [Math]::Round($_.MemoryAssigned / 1GB, 2)
                        Uptime = if ($_.Uptime) { $_.Uptime.TotalHours } else { 0 }
                        Version = $_.Version
                    }
                }
            }
        }
        
        return $hyperV
    }
    catch {
        return @{ Installed = $false; ServiceStatus = "N/A"; VMCount = 0; RunningVMs = 0; VMs = @() }
    }
}

function Obtenir-InfosReplication {
    try {
        $replication = @{
            Enabled = $false
            ReplicatingVMs = 0
            LastReplicationTime = "N/A"
            ReplicationHealth = "N/A"
        }
        
        # Verifier si la replication Hyper-V est active
        $replVMs = Get-VMReplication -ErrorAction SilentlyContinue
        if ($replVMs) {
            $replication.Enabled = $true
            $replication.ReplicatingVMs = $replVMs.Count
            
            $healthy = ($replVMs | Where-Object { $_.Health -eq "Normal" }).Count
            $replication.ReplicationHealth = "$healthy/$($replVMs.Count) Healthy"
            
            $lastRepl = $replVMs | Sort-Object LastReplicationTime -Descending | Select-Object -First 1
            if ($lastRepl -and $lastRepl.LastReplicationTime) {
                $replication.LastReplicationTime = $lastRepl.LastReplicationTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
        
        return $replication
    }
    catch {
        return @{ Enabled = $false; ReplicatingVMs = 0; LastReplicationTime = "N/A"; ReplicationHealth = "N/A" }
    }
}

function Collecter-ToutesMetriques {
    $allMetrics = @{
        Basic = @{
            SystemInfo = Obtenir-InfosSysteme
            CPU = Obtenir-MetriquesCPU
            Memory = Obtenir-MetriquesMemoire
            Disks = Obtenir-MetriquesDisques
            LastUpdate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            AgentVersion = $Script:Version
        }
        Services = Obtenir-ServicesWindows
        Events = Obtenir-EvenementsWindows
        Veeam = Obtenir-InfosVeeam
        Certificates = Obtenir-InfosCertificats
        HyperV = Obtenir-InfosHyperV
        Replication = Obtenir-InfosReplication
    }
    
    return $allMetrics
}

function Envoyer-MetriquesSharePoint {
    param(
        [hashtable]$Metriques,
        [string]$Token
    )
    
    try {
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Content-Type" = "application/json; charset=utf-8"
        }
        
        # Verifier si l'element existe deja
        $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$expand=fields"
        
        $existingItems = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop
        $existingItem = $existingItems.value | Where-Object { $_.fields.Title -eq $env:COMPUTERNAME } | Select-Object -First 1
        
        # Convertir les metriques complexes en JSON string
        $allMetrics = Collecter-ToutesMetriques
        
        $fields = @{
            "Title" = $env:COMPUTERNAME
            "Hostname" = $allMetrics.Basic.SystemInfo.Hostname
            "IPAddress" = $allMetrics.Basic.SystemInfo.IPAddress
            "State" = if ($allMetrics.Basic.CPU.Usage -gt 90 -or $allMetrics.Basic.Memory.Usage -gt 90) { "Warning" } else { "OK" }
            "CPUUsage" = $allMetrics.Basic.CPU.Usage
            "MemoryUsage" = $allMetrics.Basic.Memory.Usage
            "DiskSpaceGB" = if ($allMetrics.Basic.Disks.Count -gt 0) { $allMetrics.Basic.Disks[0].FreeGB } else { 0 }
            "Role" = if ($allMetrics.HyperV.Installed) { "Hyper-V Host" } else { "Server" }
            "HyperVStatus" = if ($allMetrics.HyperV.Installed) { "$($allMetrics.HyperV.RunningVMs)/$($allMetrics.HyperV.VMCount) VMs Running" } else { "N/A" }
            "VeeamStatus" = $allMetrics.Veeam.ServiceStatus
            "LastContact" = $allMetrics.Basic.LastUpdate
            "AgentVersion" = $allMetrics.Basic.AgentVersion
            "PendingUpdates" = $allMetrics.Events.Errors24h
        }
        
        $body = @{ fields = $fields } | ConvertTo-Json -Depth 10
        
        if ($existingItem) {
            # Update
            $itemId = $existingItem.id
            $updateUrl = "$listUrl($itemId)"
            
            $updateBody = @{
                "fields" = $fields
            }
            
            Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PATCH -Body $body -ErrorAction Stop
            Ecrire-Log "Metriques mises a jour dans SharePoint (ID: $itemId)" "SUCCES"
        }
        else {
            # Create
            Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items" `
                -Headers $headers -Method Post -Body $body -ErrorAction Stop
            Ecrire-Log "Nouvel element cree dans SharePoint" "SUCCES"
        }
        
        return $true
    }
    catch {
        Ecrire-Log "Erreur envoi SharePoint: $_" "ERREUR"
        return $false
    }
}

function Executer-Agent {
    Ecrire-Log "=== EXECUTION AGENT v$Script:Version AUTOUPDATE ===" "INFO"
    
    $token = Obtenir-Token
    if (!$token) {
        Ecrire-Log "Impossible d'obtenir le token" "ERREUR"
        return $false
    }
    
    # VERIFIER LES MISES A JOUR EN PREMIER
    Verifier-MiseAJour -Token $token
    
    # Collecter et envoyer les metriques
    $metriques = Collecter-ToutesMetriques
    Ecrire-Log "Metriques collectees" "INFO"
    
    $resultat = Envoyer-MetriquesSharePoint -Metriques $metriques -Token $token
    
    Ecrire-Log "=== FIN EXECUTION ===" "INFO"
    return $resultat
}

function Installer-Agent {
    Ecrire-Log "INSTALLATION AGENT ATLAS v$Script:Version AUTOUPDATE" "INFO"
    Ecrire-Log "==========================================" "INFO"
    
    # Creer les repertoires
    if (!(Creer-Repertoires)) {
        Ecrire-Log "Echec creation repertoires" "ERREUR"
        return
    }
    
    # Copier le script actuel
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath -and (Test-Path $scriptPath)) {
        try {
            Copy-Item -Path $scriptPath -Destination $Script:FichierAgentActuel -Force
            Ecrire-Log "Script copie vers: $Script:FichierAgentActuel" "SUCCES"
        }
        catch {
            Ecrire-Log "Erreur copie script: $_" "ERREUR"
            return
        }
    }
    
    # Supprimer anciennes taches
    Ecrire-Log "Suppression anciennes taches..." "INFO"
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        try {
            Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction Stop
            Ecrire-Log "  Tache supprimee: $($_.TaskName)" "SUCCES"
        }
        catch {
            Ecrire-Log "  Erreur suppression $($_.TaskName): $_" "AVERTISSEMENT"
        }
    }
    
    # Creer nouvelle tache avec schtasks.exe
    Ecrire-Log "Creation tache planifiee..." "INFO"
    
    $taskCommand = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script:FichierAgentActuel`" -Action Executer"
    
    $result = schtasks.exe /Create `
        /TN $Script:NomTache `
        /TR $taskCommand `
        /SC MINUTE `
        /MO $IntervalleMinutes `
        /RU SYSTEM `
        /RL HIGHEST `
        /F 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Ecrire-Log "Tache creee avec succes" "SUCCES"
        
        # Demarrer la tache
        Start-ScheduledTask -TaskName $Script:NomTache -ErrorAction SilentlyContinue
        Ecrire-Log "Tache demarree" "SUCCES"
    }
    else {
        Ecrire-Log "Erreur creation tache: $result" "ERREUR"
        return
    }
    
    # Executer une fois
    Ecrire-Log "Execution initiale..." "INFO"
    Executer-Agent
    
    Ecrire-Log "" "INFO"
    Ecrire-Log "INSTALLATION TERMINEE" "SUCCES"
    Ecrire-Log "Version: $Script:Version AUTOUPDATE" "SUCCES"
    Ecrire-Log "Intervalle: $IntervalleMinutes minutes" "SUCCES"
    Ecrire-Log "Dashboard: https://white-river-053fc6703.2.azurestaticapps.net" "INFO"
}

function Desinstaller-Agent {
    Ecrire-Log "DESINSTALLATION AGENT ATLAS" "AVERTISSEMENT"
    
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        try {
            Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false
            Ecrire-Log "Tache supprimee: $($_.TaskName)" "SUCCES"
        }
        catch {
            Ecrire-Log "Erreur suppression: $_" "ERREUR"
        }
    }
    
    Ecrire-Log "Desinstallation terminee" "SUCCES"
}

# === EXECUTION PRINCIPALE ===
switch ($Action) {
    "Installer" {
        Installer-Agent
    }
    "Desinstaller" {
        Desinstaller-Agent
    }
    "Executer" {
        Executer-Agent
    }
    default {
        Ecrire-Log "Action non reconnue: $Action" "ERREUR"
        Ecrire-Log "Actions valides: Installer, Desinstaller, Executer" "INFO"
    }
}