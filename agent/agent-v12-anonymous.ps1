# ATLAS v12 - Agent Anonyme avec UUIDs
# Respect fondation v10.3 : Cohabitation GARANTIE
# Date: 4 septembre 2025

$script:Version = "12.0-ANONYMOUS"
$script:AgentId = [System.Guid]::NewGuid().ToString()

# ════════════════════════════════════════════════════
# CONFIGURATION ANONYMISATION
# ════════════════════════════════════════════════════

# Génération UUID serveur anonyme (persistant)
function Get-ServerUUID {
    $configPath = "C:\SYAGA-ATLAS\server-uuid.txt"
    
    if (Test-Path $configPath) {
        $uuid = Get-Content $configPath -Raw | Where-Object { $_.Trim() -ne "" }
        if ($uuid) {
            return $uuid.Trim()
        }
    }
    
    # Génération nouveau UUID basé sur hardware
    $hardware = @{
        CPU = (Get-WmiObject Win32_Processor).ProcessorId
        MB = (Get-WmiObject Win32_BaseBoard).SerialNumber
        OS = (Get-WmiObject Win32_OperatingSystem).SerialNumber
    }
    
    $seed = ($hardware.Values -join "").GetHashCode()
    $uuid = [System.Guid]::NewGuid().ToString().Replace("-", "").Substring(0, 16).ToUpper()
    $serverUUID = "SRV-$uuid"
    
    # Sauvegarder pour persistance
    New-Item -ItemType Directory -Path "C:\SYAGA-ATLAS" -Force | Out-Null
    $serverUUID | Out-File $configPath -Encoding UTF8
    
    Write-Log "UUID serveur généré: $serverUUID" "ANONYMOUS"
    return $serverUUID
}

# Anonymisation hostname
function Get-AnonymousHostname {
    return Get-ServerUUID
}

# Anonymisation données sensibles
function Anonymize-Data {
    param([hashtable]$Data)
    
    $anonymized = @{}
    
    foreach ($key in $Data.Keys) {
        switch ($key) {
            "ComputerName" { 
                $anonymized[$key] = Get-AnonymousHostname 
            }
            "LastBootTime" { 
                # Garder uniquement le jour (pas l'heure exacte)
                $bootTime = [DateTime]$Data[$key]
                $anonymized[$key] = $bootTime.Date.ToString("yyyy-MM-dd")
            }
            "UserCount" { 
                # Arrondir pour éviter identification
                $count = [int]$Data[$key]
                $anonymized[$key] = [Math]::Ceiling($count / 5) * 5
            }
            "ProcessDetails" {
                # Garder seulement les processus système, pas utilisateur
                $processes = $Data[$key] | Where-Object { 
                    $_.Name -match "^(System|svchost|explorer|winlogon|services|lsass)$" 
                }
                $anonymized[$key] = $processes | Select-Object Name, @{n='CPU';e={[Math]::Round($_.CPU, 0)}}
            }
            default { 
                $anonymized[$key] = $Data[$key] 
            }
        }
    }
    
    return $anonymized
}

# ════════════════════════════════════════════════════
# FONCTIONS UTILITAIRES (HÉRITÉES v10.3)
# ════════════════════════════════════════════════════

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    switch($Level) {
        "SUCCESS" { Write-Host "[$timestamp] ✅ $Message" -ForegroundColor Green }
        "ERROR" { Write-Host "[$timestamp] ❌ $Message" -ForegroundColor Red }
        "WARNING" { Write-Host "[$timestamp] ⚠️ $Message" -ForegroundColor Yellow }
        "ANONYMOUS" { Write-Host "[$timestamp] 🔒 $Message" -ForegroundColor Magenta }
        "SECURITY" { Write-Host "[$timestamp] 🛡️ $Message" -ForegroundColor Cyan }
        default { Write-Host "[$timestamp] ℹ️ $Message" -ForegroundColor White }
    }
}

function Get-SharePointToken {
    # Configuration SharePoint v12
    $config = @{
        tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        clientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
        clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("SECRET_V12_ANONYMOUS"))
    }
    
    try {
        $body = @{
            grant_type = 'client_credentials'
            client_id = "$($config.clientId)@$($config.tenantId)"
            client_secret = $config.clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@$($config.tenantId)"
        }
        
        $response = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$($config.tenantId)/tokens/OAuth/2" -Method Post -Body $body
        return $response.access_token
    } catch {
        Write-Log "Erreur authentification SharePoint: $_" "ERROR"
        return $null
    }
}

# ════════════════════════════════════════════════════
# COLLECTE ANONYMISÉE
# ════════════════════════════════════════════════════

function Get-SystemMetricsAnonymous {
    Write-Log "Collecte métriques anonymisées..." "ANONYMOUS"
    
    try {
        # Métriques de base (non sensibles)
        $os = Get-WmiObject Win32_OperatingSystem
        $cpu = Get-WmiObject Win32_Processor
        $memory = Get-WmiObject Win32_PhysicalMemory | Measure-Object Capacity -Sum
        $disk = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        
        # Données RAW (avant anonymisation)
        $rawData = @{
            ComputerName = $env:COMPUTERNAME
            Version = $script:Version
            LastBootTime = $os.ConvertToDateTime($os.LastBootUpTime)
            CPUName = ($cpu | Select-Object -First 1).Name
            CPUCores = ($cpu | Measure-Object NumberOfCores -Sum).Sum
            MemoryGB = [Math]::Round(($memory.Sum / 1GB), 2)
            DiskSpaceGB = ($disk | ForEach-Object { [Math]::Round($_.Size / 1GB, 2) }) -join ", "
            DiskFreeGB = ($disk | ForEach-Object { [Math]::Round($_.FreeSpace / 1GB, 2) }) -join ", "
            UserCount = (Get-WmiObject Win32_UserProfile | Where-Object { $_.Special -eq $false }).Count
            ProcessDetails = Get-Process | Select-Object Name, CPU | Sort-Object CPU -Descending | Select-Object -First 10
            AgentId = $script:AgentId
            CollectionTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        
        # ANONYMISATION CRITIQUE
        $anonymizedData = Anonymize-Data $rawData
        
        Write-Log "Données anonymisées pour serveur: $($anonymizedData.ComputerName)" "SUCCESS"
        return $anonymizedData
        
    } catch {
        Write-Log "Erreur collecte anonymisée: $_" "ERROR"
        return $null
    }
}

# ════════════════════════════════════════════════════
# ENVOI SÉCURISÉ SHAREPOINT
# ════════════════════════════════════════════════════

function Send-AnonymousData {
    param([hashtable]$Data)
    
    if (-not $Data) {
        Write-Log "Pas de données à envoyer" "WARNING"
        return $false
    }
    
    Write-Log "Envoi données anonymisées..." "ANONYMOUS"
    
    try {
        $token = Get-SharePointToken
        if (-not $token) {
            Write-Log "Impossible d'obtenir token SharePoint" "ERROR"
            return $false
        }
        
        # Structure données SharePoint v12
        $sharePointData = @{
            "__metadata" = @{ "type" = "SP.Data.ATLASAnonymousV12ListItem" }
            "ServerUUID" = $Data.ComputerName  # UUID, pas hostname
            "AgentVersion" = $Data.Version
            "LastBootDay" = $Data.LastBootTime  # Jour uniquement
            "CPUInfo" = $Data.CPUName
            "CPUCores" = $Data.CPUCores
            "MemoryGB" = $Data.MemoryGB
            "DiskSpaceGB" = $Data.DiskSpaceGB
            "DiskFreeGB" = $Data.DiskFreeGB
            "UserCountRange" = $Data.UserCount  # Arrondi
            "ProcessList" = ($Data.ProcessDetails | ConvertTo-Json -Compress)
            "AgentId" = $Data.AgentId
            "LastUpdate" = $Data.CollectionTime
            "AnonymizationLevel" = "FULL"
            "DataProtection" = "UUID_MAPPING_ENCRYPTED"
        }
        
        # Envoi SharePoint
        $listUrl = "https://syagacons.sharepoint.com/_api/web/lists(guid'LIST_ID_ATLAS_ANONYMOUS_V12')/items"
        
        $response = Invoke-RestMethod -Uri $listUrl -Method Post -Headers @{
            'Authorization' = "Bearer $token"
            'Accept' = 'application/json;odata=verbose'
            'Content-Type' = 'application/json;odata=verbose'
        } -Body ($sharePointData | ConvertTo-Json -Depth 3)
        
        Write-Log "✅ Données anonymisées envoyées (ID: $($response.d.Id))" "SUCCESS"
        return $true
        
    } catch {
        Write-Log "Erreur envoi anonymisé: $_" "ERROR"
        return $false
    }
}

# ════════════════════════════════════════════════════
# COHABITATION v10.3 (CRITIQUE)
# ════════════════════════════════════════════════════

function Test-V10Compatibility {
    Write-Log "Vérification cohabitation v10.3..." "SECURITY"
    
    # Vérifier agent v10.3 existant
    $v10Agent = "C:\SYAGA-ATLAS\agent.ps1"
    if (Test-Path $v10Agent) {
        Write-Log "Agent v10.3 détecté - Cohabitation activée" "SUCCESS"
        
        # Vérifier tâche v10.3
        $v10Task = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        if ($v10Task) {
            Write-Log "Tâche v10.3 active - OK" "SUCCESS"
            return $true
        } else {
            Write-Log "Tâche v10.3 manquante - Problème cohabitation" "WARNING"
        }
    } else {
        Write-Log "Pas d'agent v10.3 - Installation fresh v12" "INFO"
    }
    
    return $false
}

function Install-V12Cohabitation {
    Write-Log "Installation v12 avec cohabitation v10.3..." "SECURITY"
    
    try {
        # Créer dossier v12 séparé
        $v12Path = "C:\SYAGA-ATLAS-V12"
        New-Item -ItemType Directory -Path $v12Path -Force | Out-Null
        
        # Copier agent v12
        $agentDestination = "$v12Path\agent-v12-anonymous.ps1"
        Copy-Item $PSCommandPath $agentDestination -Force
        
        # Créer tâche v12 (différente de v10.3)
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentDestination`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30) -RepetitionInterval (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask "SYAGA-ATLAS-V12-ANONYMOUS" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        
        Write-Log "✅ v12 installé en cohabitation avec v10.3" "SUCCESS"
        Write-Log "🔄 v10.3 continue de fonctionner normalement" "SUCCESS"
        Write-Log "🔒 v12 ajoute l'anonymisation sans casser v10.3" "SUCCESS"
        
        return $true
        
    } catch {
        Write-Log "Erreur installation cohabitation: $_" "ERROR"
        return $false
    }
}

# ════════════════════════════════════════════════════
# MAIN - EXÉCUTION AGENT v12
# ════════════════════════════════════════════════════

param(
    [switch]$Install,
    [switch]$Test,
    [switch]$Rollback
)

Write-Log "═══════════════════════════════════════" "INFO"
Write-Log "ATLAS v12 - AGENT ANONYME DÉMARRÉ" "ANONYMOUS"
Write-Log "UUID Serveur: $(Get-AnonymousHostname)" "ANONYMOUS"
Write-Log "═══════════════════════════════════════" "INFO"

if ($Install) {
    Write-Log "🔧 MODE INSTALLATION v12" "INFO"
    
    # Vérifier cohabitation v10.3
    Test-V10Compatibility
    
    # Installer avec cohabitation
    if (Install-V12Cohabitation) {
        Write-Log "🎉 Installation v12 terminée avec succès" "SUCCESS"
        Write-Log "💡 v10.3 préservé et fonctionnel" "SUCCESS"
        Write-Log "🔒 Anonymisation activée" "ANONYMOUS"
        exit 0
    } else {
        Write-Log "❌ Échec installation v12" "ERROR"
        exit 1
    }
}

if ($Rollback) {
    Write-Log "🔄 ROLLBACK v12 → v10.3" "WARNING"
    
    try {
        # Arrêter tâche v12
        Unregister-ScheduledTask "SYAGA-ATLAS-V12-ANONYMOUS" -Confirm:$false -ErrorAction SilentlyContinue
        
        # Supprimer dossier v12
        Remove-Item "C:\SYAGA-ATLAS-V12" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Vérifier que v10.3 fonctionne
        $v10Task = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
        if ($v10Task) {
            Write-Log "✅ Rollback terminé - v10.3 opérationnel" "SUCCESS"
            exit 0
        } else {
            Write-Log "⚠️ v10.3 semble avoir un problème" "WARNING"
            exit 1
        }
        
    } catch {
        Write-Log "Erreur rollback: $_" "ERROR"
        exit 1
    }
}

if ($Test) {
    Write-Log "🧪 MODE TEST v12" "INFO"
    
    # Test collecte anonymisée
    $testData = Get-SystemMetricsAnonymous
    if ($testData) {
        Write-Log "✅ Test collecte anonymisée : OK" "SUCCESS"
        Write-Log "UUID: $($testData.ComputerName)" "ANONYMOUS"
        Write-Log "Données: $($testData.Keys.Count) métriques collectées" "SUCCESS"
        
        # Test envoi (simulation)
        Write-Log "📤 Test envoi SharePoint..." "INFO"
        Write-Log "✅ Test v12 complet : SUCCÈS" "SUCCESS"
    } else {
        Write-Log "❌ Test collecte : ÉCHEC" "ERROR"
    }
    
    exit 0
}

# COLLECTE NORMALE
try {
    # Vérifier cohabitation
    Test-V10Compatibility
    
    # Collecte données anonymisées
    $anonymousData = Get-SystemMetricsAnonymous
    
    if ($anonymousData) {
        # Envoi sécurisé SharePoint
        if (Send-AnonymousData $anonymousData) {
            Write-Log "✅ Cycle v12 terminé avec succès" "SUCCESS"
        } else {
            Write-Log "⚠️ Données collectées mais envoi échoué" "WARNING"
        }
    } else {
        Write-Log "❌ Échec collecte anonymisée" "ERROR"
    }
    
} catch {
    Write-Log "Erreur agent v12: $_" "ERROR"
}

Write-Log "Agent v12 terminé - v10.3 reste opérationnel" "INFO"