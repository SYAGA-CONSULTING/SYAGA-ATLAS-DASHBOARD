# ATLAS Agent v5.6 FINAL - Auto-update VRAIMENT automatique via SharePoint
# L'agent se met a jour UNIQUEMENT depuis le dashboard, JAMAIS manuellement !

param(
    [string]$Action = "Executer",
    [int]$IntervalleMinutes = 3
)

# Configuration
$Script:Version = "5.6-FINAL"
$Script:CheminBase = "C:\ATLAS"
$Script:CheminAgent = "$Script:CheminBase\Agent"
$Script:CheminLogs = "$Script:CheminBase\Logs"
$Script:FichierLog = "$Script:CheminLogs\Agent-$(Get-Date -Format 'yyyyMMdd').log"
$Script:FichierAgentActuel = "$Script:CheminAgent\ATLAS-Agent-Current.ps1"
$Script:NomTache = "ATLAS-Agent-v5"

# SharePoint
$Script:TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$Script:ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
$Script:ClientSecret = "" # Lu depuis config.json
$Script:ConfigFile = "$Script:CheminBase\config.json"

# IMPORTANT: Les updates viennent de SharePoint, PAS de GitHub !
$Script:SharePointLists = @{
    Servers = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"  # Liste des serveurs et metriques
    Updates = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"  # Meme liste pour les configs/updates
}

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
        if (!(Test-Path $_)) {
            try {
                New-Item -ItemType Directory -Path $_ -Force -ErrorAction Stop | Out-Null
                Ecrire-Log "Repertoire cree: $_" "SUCCES"
            }
            catch {
                Ecrire-Log "Erreur creation $_ : $_" "ERREUR"
                $success = $false
            }
        }
    }
    return $success
}

function Charger-Configuration {
    if ([string]::IsNullOrEmpty($Script:ClientSecret)) {
        if (Test-Path $Script:ConfigFile) {
            try {
                $config = Get-Content $Script:ConfigFile -Raw | ConvertFrom-Json
                if ($config.ClientSecret) {
                    $Script:ClientSecret = $config.ClientSecret
                    Ecrire-Log "Configuration chargee" "DEBUG"
                }
            }
            catch {
                Ecrire-Log "Erreur lecture config: $_" "AVERTISSEMENT"
            }
        }
        else {
            # Créer config par défaut
            $defaultConfig = @{
                ClientId = $Script:ClientId
                TenantId = $Script:TenantId
                ClientSecret = "AJOUTER_LE_SECRET_ICI"
                SiteUrl = "https://syagaconsulting.sharepoint.com/sites/SYAGA-Atlas"
            }
            
            $defaultConfig | ConvertTo-Json | Out-File -FilePath $Script:ConfigFile -Encoding UTF8
            Ecrire-Log "Config creee - AJOUTER LE SECRET dans $Script:ConfigFile" "ERREUR"
        }
    }
}

function Obtenir-Token {
    try {
        Charger-Configuration
        
        if ([string]::IsNullOrEmpty($Script:ClientSecret) -or $Script:ClientSecret -eq "AJOUTER_LE_SECRET_ICI") {
            Ecrire-Log "ClientSecret non configure" "ERREUR"
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
        Ecrire-Log "Erreur token: $_" "ERREUR"
        return $null
    }
}

# ========== FONCTION AUTO-UPDATE CRITIQUE ==========
function Verifier-MiseAJour-SharePoint {
    param($Token)
    
    try {
        Ecrire-Log "=== VERIFICATION AUTO-UPDATE SHAREPOINT ===" "UPDATE"
        
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Content-Type" = "application/json"
        }
        
        # Récupérer TOUTES les entrées depuis SharePoint
        $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/$($Script:SharePointLists.Updates)/items?`$expand=fields"
        
        $response = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop
        
        # Chercher l'entrée UPDATE_CONFIG
        $updateConfig = $response.value | Where-Object { 
            $_.fields.Title -eq "UPDATE_CONFIG" -or 
            $_.fields.Hostname -eq "UPDATE_CONFIG"
        } | Select-Object -First 1
        
        if ($updateConfig) {
            $targetVersion = $updateConfig.fields.AgentVersion
            $updateCode = $updateConfig.fields.VeeamStatus  # On utilise un champ existant pour stocker le code
            
            Ecrire-Log "Config trouvee - Version cible: $targetVersion (actuelle: $Script:Version)" "UPDATE"
            
            # Nettoyer les versions pour comparaison
            $currentClean = $Script:Version -replace '^v', '' -replace '-', ''
            $targetClean = $targetVersion -replace '^v', '' -replace '-', ''
            
            # Si nouvelle version différente ET code disponible
            if ($targetClean -ne $currentClean -and $updateCode -and $updateCode -ne "N/A") {
                Ecrire-Log "NOUVELLE VERSION DISPONIBLE: $targetVersion" "UPDATE"
                
                # Decoder le code Base64
                try {
                    $scriptContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($updateCode))
                    
                    # Sauvegarder le nouveau script
                    $scriptContent | Out-File -FilePath $Script:FichierAgentActuel -Encoding UTF8 -Force
                    
                    Ecrire-Log "Agent mis a jour vers v$targetVersion avec succes !" "SUCCES"
                    Ecrire-Log "REDEMARRAGE POUR APPLIQUER LA MISE A JOUR..." "UPDATE"
                    
                    # Redémarrer la tâche
                    Restart-ScheduledTask -TaskName $Script:NomTache -ErrorAction SilentlyContinue
                    
                    # Arrêter ce script
                    exit 0
                }
                catch {
                    Ecrire-Log "Erreur decodage/installation: $_" "ERREUR"
                }
            }
            else {
                Ecrire-Log "Agent deja a jour ou pas de code disponible" "DEBUG"
            }
        }
        else {
            Ecrire-Log "Pas de configuration UPDATE_CONFIG dans SharePoint" "DEBUG"
        }
    }
    catch {
        Ecrire-Log "Erreur verification update: $_" "AVERTISSEMENT"
    }
}

function Obtenir-InfosSysteme {
    @{
        Hostname = $env:COMPUTERNAME
        IPAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        OS = (Get-CimInstance Win32_OperatingSystem).Caption
        Domaine = (Get-CimInstance Win32_ComputerSystem).Domain
    }
}

function Obtenir-MetriquesCPU {
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        @{
            Usage = [Math]::Round($cpu.LoadPercentage, 2)
            Cores = $cpu.NumberOfCores
        }
    }
    catch {
        @{ Usage = 0; Cores = 0 }
    }
}

function Obtenir-MetriquesMemoire {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMem = $os.TotalVisibleMemorySize / 1MB
        $freeMem = $os.FreePhysicalMemory / 1MB
        $usedMem = $totalMem - $freeMem
        $usage = [Math]::Round(($usedMem / $totalMem) * 100, 2)
        
        @{
            Usage = $usage
            TotalGB = [Math]::Round($totalMem / 1024, 2)
            FreeGB = [Math]::Round($freeMem / 1024, 2)
        }
    }
    catch {
        @{ Usage = 0; TotalGB = 0; FreeGB = 0 }
    }
}

function Obtenir-MetriquesDisques {
    try {
        $disques = @()
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $freeGB = [Math]::Round($_.FreeSpace / 1GB, 2)
            $totalGB = [Math]::Round($_.Size / 1GB, 2)
            
            $disques += @{
                Drive = $_.DeviceID
                FreeGB = $freeGB
                TotalGB = $totalGB
                UsagePercent = if ($totalGB -gt 0) { [Math]::Round((($totalGB - $freeGB) / $totalGB) * 100, 2) } else { 0 }
            }
        }
        $disques
    }
    catch {
        @()
    }
}

function Collecter-Metriques {
    $sysInfo = Obtenir-InfosSysteme
    $cpu = Obtenir-MetriquesCPU
    $mem = Obtenir-MetriquesMemoire
    $disks = Obtenir-MetriquesDisques
    
    @{
        Hostname = $sysInfo.Hostname
        IPAddress = $sysInfo.IPAddress
        State = if ($cpu.Usage -gt 90 -or $mem.Usage -gt 90) { "Warning" } else { "OK" }
        CPUUsage = $cpu.Usage
        MemoryUsage = $mem.Usage
        DiskSpaceGB = if ($disks.Count -gt 0) { $disks[0].FreeGB } else { 0 }
        Role = "Server"
        HyperVStatus = "N/A"
        VeeamStatus = "N/A"
        LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        AgentVersion = $Script:Version
        PendingUpdates = 0
    }
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
        
        # Chercher si le serveur existe deja
        $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/$($Script:SharePointLists.Servers)/items?`$expand=fields"
        
        $existingItems = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop
        $existingItem = $existingItems.value | Where-Object { $_.fields.Title -eq $env:COMPUTERNAME } | Select-Object -First 1
        
        $fields = @{
            "Title" = $env:COMPUTERNAME
            "Hostname" = $Metriques.Hostname
            "IPAddress" = $Metriques.IPAddress
            "State" = $Metriques.State
            "CPUUsage" = $Metriques.CPUUsage
            "MemoryUsage" = $Metriques.MemoryUsage
            "DiskSpaceGB" = $Metriques.DiskSpaceGB
            "Role" = $Metriques.Role
            "HyperVStatus" = $Metriques.HyperVStatus
            "VeeamStatus" = $Metriques.VeeamStatus
            "LastContact" = $Metriques.LastContact
            "AgentVersion" = $Metriques.AgentVersion
            "PendingUpdates" = $Metriques.PendingUpdates
        }
        
        $body = @{ fields = $fields } | ConvertTo-Json -Depth 10
        
        if ($existingItem) {
            # Update
            $itemId = $existingItem.id
            $updateUrl = "$listUrl($itemId)"
            Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PATCH -Body $body -ErrorAction Stop
            Ecrire-Log "Metriques mises a jour (ID: $itemId)" "SUCCES"
        }
        else {
            # Create
            Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/$($Script:SharePointLists.Servers)/items" `
                -Headers $headers -Method Post -Body $body -ErrorAction Stop
            Ecrire-Log "Nouvel element cree" "SUCCES"
        }
        
        return $true
    }
    catch {
        Ecrire-Log "Erreur SharePoint: $_" "ERREUR"
        return $false
    }
}

function Executer-Agent {
    Ecrire-Log "=== EXECUTION AGENT v$Script:Version ===" "INFO"
    
    $token = Obtenir-Token
    if (!$token) {
        Ecrire-Log "Pas de token - verifiez config.json" "ERREUR"
        return $false
    }
    
    # PRIORITE 1: VERIFIER LES MISES A JOUR !
    Verifier-MiseAJour-SharePoint -Token $token
    
    # Ensuite envoyer les metriques
    $metriques = Collecter-Metriques
    $resultat = Envoyer-MetriquesSharePoint -Metriques $metriques -Token $token
    
    Ecrire-Log "=== FIN EXECUTION ===" "INFO"
    return $resultat
}

function Installer-Agent {
    Ecrire-Log "INSTALLATION AGENT ATLAS v$Script:Version" "INFO"
    Ecrire-Log "==========================================" "INFO"
    
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
            Ecrire-Log "Erreur copie: $_" "ERREUR"
            return
        }
    }
    
    # Supprimer anciennes taches
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        try {
            Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction Stop
            Ecrire-Log "Tache supprimee: $($_.TaskName)" "SUCCES"
        }
        catch {}
    }
    
    # Creer nouvelle tache
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
        Ecrire-Log "Tache creee" "SUCCES"
        Start-ScheduledTask -TaskName $Script:NomTache -ErrorAction SilentlyContinue
        Ecrire-Log "Tache demarree" "SUCCES"
    }
    else {
        Ecrire-Log "Erreur creation tache: $result" "ERREUR"
        return
    }
    
    # Executer une fois
    Executer-Agent
    
    Ecrire-Log "" "INFO"
    Ecrire-Log "INSTALLATION TERMINEE" "SUCCES"
    Ecrire-Log "Version: $Script:Version" "SUCCES"
    Ecrire-Log "Auto-update: ACTIF (depuis SharePoint)" "SUCCES"
    Ecrire-Log "Dashboard: https://white-river-053fc6703.2.azurestaticapps.net" "INFO"
}

# === EXECUTION PRINCIPALE ===
switch ($Action) {
    "Installer" {
        Installer-Agent
    }
    "Executer" {
        Executer-Agent
    }
    default {
        Ecrire-Log "Action non reconnue: $Action" "ERREUR"
    }
}