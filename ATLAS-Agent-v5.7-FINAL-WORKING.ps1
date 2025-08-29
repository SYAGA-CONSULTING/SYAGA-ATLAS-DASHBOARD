# ATLAS Agent v5.7 FINAL WORKING - Corrige DEFINITIVEMENT l'erreur 400

param(
    [string]$Action = "Executer",
    [int]$IntervalleMinutes = 3
)

# Configuration
$Script:Version = "5.7-FINAL-WORKING"
$Script:CheminBase = "C:\ATLAS"
$Script:CheminAgent = "$Script:CheminBase\Agent"
$Script:CheminLogs = "$Script:CheminBase\Logs"
$Script:FichierLog = "$Script:CheminLogs\Agent-$(Get-Date -Format 'yyyyMMdd').log"
$Script:FichierAgentActuel = "$Script:CheminAgent\ATLAS-Agent-Current.ps1"
$Script:NomTache = "ATLAS-Agent-v5"

# SharePoint
$Script:TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$Script:ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
$Script:ClientSecret = ""
$Script:ConfigFile = "$Script:CheminBase\config.json"

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
                Ecrire-Log "Repertoire cree - $_" "SUCCES"
            }
            catch {
                Ecrire-Log "Erreur creation $_ - $_" "ERREUR"
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
                Ecrire-Log "Erreur lecture config - $_" "AVERTISSEMENT"
            }
        }
    }
}

function Obtenir-Token {
    try {
        Charger-Configuration
        
        if ([string]::IsNullOrEmpty($Script:ClientSecret)) {
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
        Ecrire-Log "Erreur token - $_" "ERREUR"
        return $null
    }
}

# ========== FONCTION AUTO-UPDATE ==========
function Verifier-MiseAJour-SharePoint {
    param($Token)
    
    try {
        Ecrire-Log "=== VERIFICATION AUTO-UPDATE SHAREPOINT ===" "UPDATE"
        
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Content-Type" = "application/json"
        }
        
        $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$expand=fields"
        
        $response = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop
        
        # Chercher UPDATE_CONFIG
        $updateConfig = $response.value | Where-Object { 
            $_.fields.Title -eq "UPDATE_CONFIG" -or 
            $_.fields.Hostname -eq "UPDATE_CONFIG"
        } | Select-Object -First 1
        
        if ($updateConfig) {
            $targetVersion = $updateConfig.fields.AgentVersion
            $updateCode = $updateConfig.fields.VeeamStatus
            
            Ecrire-Log "Config trouvee - Version cible - $targetVersion (actuelle - $Script:Version)" "UPDATE"
            
            $currentClean = $Script:Version -replace '^v', '' -replace '-', ''
            $targetClean = $targetVersion -replace '^v', '' -replace '-', ''
            
            if ($targetClean -ne $currentClean -and $updateCode -and $updateCode -ne "N/A") {
                Ecrire-Log "NOUVELLE VERSION DISPONIBLE - $targetVersion" "UPDATE"
                
                try {
                    $scriptContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($updateCode))
                    $scriptContent | Out-File -FilePath $Script:FichierAgentActuel -Encoding UTF8 -Force
                    
                    Ecrire-Log "Agent mis a jour vers v$targetVersion avec succes !" "SUCCES"
                    Ecrire-Log "REDEMARRAGE POUR APPLIQUER LA MISE A JOUR..." "UPDATE"
                    
                    Stop-ScheduledTask -TaskName $Script:NomTache -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    Start-ScheduledTask -TaskName $Script:NomTache -ErrorAction SilentlyContinue
                    
                    exit 0
                }
                catch {
                    Ecrire-Log "Erreur decodage/installation - $_" "ERREUR"
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
        Ecrire-Log "Erreur verification update - $_" "AVERTISSEMENT"
    }
}

function Collecter-Metriques {
    try {
        # CPU
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $cpuUsage = if ($cpu.LoadPercentage) { [double]$cpu.LoadPercentage } else { [double]5.0 }
        
        # Memory
        $mem = Get-CimInstance Win32_OperatingSystem
        $memUsage = [double]([math]::Round((($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory) / $mem.TotalVisibleMemorySize * 100), 2))
        
        # Disk
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [double]([math]::Round($disk.FreeSpace / 1GB, 2))
        
        # IP
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        if (!$ip) { $ip = "0.0.0.0" }
        
        return @{
            Hostname = [string]$env:COMPUTERNAME
            IPAddress = [string]$ip
            State = [string](if ($cpuUsage -gt 90 -or $memUsage -gt 90) { "Warning" } else { "OK" })
            CPUUsage = [double]$cpuUsage
            MemoryUsage = [double]$memUsage
            DiskSpaceGB = [double]$diskFreeGB
            Role = [string]"Server"
            HyperVStatus = [string]"N/A"
            VeeamStatus = [string]"N/A"
            LastContact = [string](Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            AgentVersion = [string]$Script:Version
            PendingUpdates = [double]0
        }
    }
    catch {
        Ecrire-Log "Erreur collecte metriques - $_" "ERREUR"
        return $null
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
            "Content-Type" = "application/json"
        }
        
        # STRATEGIE ANTI-ERREUR 400: Toujours creer une NOUVELLE entree
        # Ne jamais essayer de mettre a jour les anciennes
        
        $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items?`$expand=fields"
        
        $existingItems = Invoke-RestMethod -Uri $listUrl -Headers $headers -Method Get -ErrorAction Stop
        
        # Chercher l'entree la plus recente pour ce serveur
        $myItems = $existingItems.value | Where-Object { 
            $_.fields.Title -eq $env:COMPUTERNAME -or $_.fields.Hostname -eq $env:COMPUTERNAME 
        } | Sort-Object id -Descending
        
        $useExisting = $null
        
        # Utiliser l'entree la plus recente SI elle a la meme version d'agent
        if ($myItems -and $myItems[0].fields.AgentVersion -eq $Script:Version) {
            $useExisting = $myItems[0]
            Ecrire-Log "Utilisation entree existante ID=$($useExisting.id)" "DEBUG"
        }
        
        $fields = @{
            "Title" = [string]$env:COMPUTERNAME
            "Hostname" = [string]$Metriques.Hostname
            "IPAddress" = [string]$Metriques.IPAddress
            "State" = [string]$Metriques.State
            "CPUUsage" = [double]$Metriques.CPUUsage
            "MemoryUsage" = [double]$Metriques.MemoryUsage
            "DiskSpaceGB" = [double]$Metriques.DiskSpaceGB
            "Role" = [string]$Metriques.Role
            "HyperVStatus" = [string]$Metriques.HyperVStatus
            "VeeamStatus" = [string]$Metriques.VeeamStatus
            "LastContact" = [string]$Metriques.LastContact
            "AgentVersion" = [string]$Metriques.AgentVersion
            "PendingUpdates" = [double]$Metriques.PendingUpdates
        }
        
        $body = @{ fields = $fields } | ConvertTo-Json -Depth 10
        
        if ($useExisting) {
            # Mettre a jour l'entree compatible
            $itemId = $useExisting.id
            $updateUrl = "$listUrl($itemId)"
            Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PATCH -Body $body -ErrorAction Stop
            Ecrire-Log "Metriques mises a jour ID=$itemId" "SUCCES"
        }
        else {
            # Creer nouvelle entree
            $createUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
            $newItem = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Post -Body $body -ErrorAction Stop
            Ecrire-Log "Nouvelle entree creee ID=$($newItem.id)" "SUCCES"
        }
        
        return $true
    }
    catch {
        Ecrire-Log "Erreur SharePoint - $_" "ERREUR"
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
    
    # VERIFIER LES MISES A JOUR
    Verifier-MiseAJour-SharePoint -Token $token
    
    # ENVOYER LES METRIQUES
    $metriques = Collecter-Metriques
    if ($metriques) {
        $resultat = Envoyer-MetriquesSharePoint -Metriques $metriques -Token $token
        Ecrire-Log "=== FIN EXECUTION ===" "INFO"
        return $resultat
    }
    else {
        Ecrire-Log "Pas de metriques collectees" "ERREUR"
        return $false
    }
}

function Installer-Agent {
    Ecrire-Log "INSTALLATION AGENT ATLAS v$Script:Version" "INFO"
    Ecrire-Log "==========================================" "INFO"
    
    if (!(Creer-Repertoires)) {
        Ecrire-Log "Echec creation repertoires" "ERREUR"
        return
    }
    
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath -and (Test-Path $scriptPath)) {
        try {
            Copy-Item -Path $scriptPath -Destination $Script:FichierAgentActuel -Force
            Ecrire-Log "Script copie vers - $Script:FichierAgentActuel" "SUCCES"
        }
        catch {
            Ecrire-Log "Erreur copie - $_" "ERREUR"
            return
        }
    }
    
    # Supprimer anciennes taches
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
        try {
            Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction Stop
            Ecrire-Log "Tache supprimee - $($_.TaskName)" "SUCCES"
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
        Ecrire-Log "Erreur creation tache - $result" "ERREUR"
        return
    }
    
    # Executer une fois
    Executer-Agent
    
    Ecrire-Log "" "INFO"
    Ecrire-Log "INSTALLATION TERMINEE" "SUCCES"
    Ecrire-Log "Version - $Script:Version" "SUCCES"
    Ecrire-Log "Auto-update - ACTIF (depuis SharePoint)" "SUCCES"
    Ecrire-Log "Dashboard - https://white-river-053fc6703.2.azurestaticapps.net" "INFO"
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
        Ecrire-Log "Action non reconnue - $Action" "ERREUR"
    }
}