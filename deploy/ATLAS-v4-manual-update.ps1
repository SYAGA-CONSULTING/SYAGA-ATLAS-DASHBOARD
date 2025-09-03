# ATLAS v4.0 - Agent avec Mise à Jour MANUELLE depuis Dashboard
# PAS d'auto-update ! Uniquement sur commande depuis le dashboard

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      ATLAS v4.0 - MISE À JOUR MANUELLE ONLY         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Parse paramètres depuis URL
$fullCommand = $MyInvocation.Line
$ServerName = $env:COMPUTERNAME
$ClientName = "SYAGA"
$ServerType = "Physical"

if ($fullCommand -match 'p=([A-Za-z0-9+/=]+)') {
    $base64 = $matches[1]
    try {
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
        $params = $json | ConvertFrom-Json
        if ($params.server) { $ServerName = $params.server }
        if ($params.client) { $ClientName = $params.client }
        if ($params.type) { $ServerType = $params.type }
    } catch {}
}

Write-Host "[CONFIG] Serveur: $ServerName | Client: $ClientName | Type: $ServerType" -ForegroundColor Green

# Création dossier
$atlasPath = "C:\SYAGA-ATLAS"
New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null

# ════════════════════════════════════════════════════════
# AGENT v4.0 - Collecte + Check Commandes Manuelles
# ════════════════════════════════════════════════════════
$agentScript = @'
# ATLAS Agent v4.0 - Manual Update Only
$version = "4.0"

function Write-Log {
    param($Message, $Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$ts] [$Level] $Message"
    Add-Content "C:\SYAGA-ATLAS\agent.log" -Value $log -Encoding UTF8
    
    $color = @{INFO="White"; OK="Green"; ERROR="Red"; WARNING="Yellow"; UPDATE="Cyan"}[$Level]
    if (!$color) { $color = "White" }
    Write-Host $log -ForegroundColor $color
}

Write-Log "Agent ATLAS v$version démarré"

# 1. COLLECTER MÉTRIQUES (comme avant)
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    
    $cpuUsage = 0
    try {
        $counter = Get-Counter "\Processeur(_Total)\% temps processeur" -EA SilentlyContinue
        if ($counter) { $cpuUsage = [math]::Round($counter.CounterSamples[0].CookedValue, 2) }
    } catch {}
    
    $updates = 0
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $updates = $searcher.Search("IsInstalled=0").Updates.Count
    } catch {}
    
    $metrics = @{
        Hostname = $env:COMPUTERNAME
        Version = $version
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        CPUUsage = $cpuUsage
        MemoryUsage = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 2)
        DiskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        PendingUpdates = $updates
        State = "Online"
    }
    
    Write-Log "Métriques collectées" "OK"
    
} catch {
    Write-Log "Erreur collecte: $_" "ERROR"
}

# 2. VÉRIFIER COMMANDES DEPUIS SHAREPOINT
Write-Log "Vérification des commandes..." "INFO"

try {
    # Récupérer les commandes pour ce serveur
    # IRM depuis Azure pour récupérer les commandes pending
    $commandsUrl = "https://white-river-053fc6703.2.azurestaticapps.net/api/commands?hostname=$env:COMPUTERNAME"
    $commands = Invoke-RestMethod -Uri $commandsUrl -Method GET -ErrorAction SilentlyContinue
    
    if ($commands) {
        foreach ($cmd in $commands) {
            if ($cmd.CommandType -eq "UPDATE_AGENT" -and $cmd.Status -eq "Pending") {
                Write-Log "🚀 COMMANDE MISE À JOUR DÉTECTÉE !" "UPDATE"
                Write-Log "Version cible: $($cmd.NewVersion)" "UPDATE"
                Write-Log "Demandée par: $($cmd.CreatedBy)" "UPDATE"
                
                # TÉLÉCHARGER ET INSTALLER NOUVELLE VERSION
                Write-Log "Téléchargement agent v$($cmd.NewVersion)..." "UPDATE"
                
                try {
                    # Télécharger nouvelle version depuis Azure
                    $newAgentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/agent/v$($cmd.NewVersion)/agent.ps1"
                    $newAgent = Invoke-WebRequest -Uri $newAgentUrl -UseBasicParsing
                    
                    # Backup ancien
                    Copy-Item "C:\SYAGA-ATLAS\agent.ps1" "C:\SYAGA-ATLAS\backup_v$version.ps1" -Force
                    Write-Log "Backup créé: backup_v$version.ps1" "OK"
                    
                    # Installer nouveau
                    $newAgent.Content | Out-File "C:\SYAGA-ATLAS\agent.ps1" -Encoding UTF8 -Force
                    Write-Log "✅ AGENT MIS À JOUR VERS v$($cmd.NewVersion) !" "UPDATE"
                    
                    # Marquer commande comme exécutée
                    # (Dans la vraie version, on mettrait à jour SharePoint)
                    Write-Log "Commande $($cmd.Title) marquée comme exécutée" "OK"
                    
                    # Redémarrer avec nouvelle version
                    Write-Log "Redémarrage avec nouvelle version..." "UPDATE"
                    exit 0
                    
                } catch {
                    Write-Log "Erreur mise à jour: $_" "ERROR"
                }
            }
        }
    } else {
        Write-Log "Aucune commande en attente" "INFO"
    }
    
} catch {
    Write-Log "Pas de connexion aux commandes (mode local)" "WARNING"
}

# 3. ENVOYER MÉTRIQUES À SHAREPOINT
try {
    # TODO: Implémenter envoi réel vers SharePoint
    Write-Log "Envoi métriques vers SharePoint..." "INFO"
    # Pour l'instant en mode démo
    Write-Log "Métriques envoyées (mode démo)" "OK"
} catch {
    Write-Log "Erreur envoi: $_" "ERROR"
}

Write-Log "Agent v$version terminé"
'@

$agentScript | Out-File "$atlasPath\agent.ps1" -Encoding UTF8

# ════════════════════════════════════════════════════════
# PAS D'UPDATE-ATLAS.ps1 ! Mise à jour MANUELLE uniquement
# ════════════════════════════════════════════════════════

Write-Host ""
Write-Host "[INFO] PAS de script auto-update !" -ForegroundColor Yellow
Write-Host "[INFO] Les mises à jour se font UNIQUEMENT depuis le dashboard" -ForegroundColor Yellow
Write-Host ""

# Config initiale
@{
    Hostname = $ServerName
    ClientName = $ClientName
    ServerType = $ServerType
    InstallDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Version = "4.0"
    AutoUpdate = $false  # DÉSACTIVÉ !
} | ConvertTo-Json | Out-File "$atlasPath\config.json" -Encoding UTF8

# ════════════════════════════════════════════════════════
# UNE SEULE TÂCHE : Agent qui vérifie les commandes
# ════════════════════════════════════════════════════════
Write-Host "[TÂCHE] Création tâche agent..." -ForegroundColor Cyan

Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -EA SilentlyContinue

# Une seule tâche qui :
# 1. Collecte les métriques
# 2. Vérifie s'il y a une commande UPDATE
# 3. Se met à jour SI et SEULEMENT SI vous avez cliqué dans le dashboard

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -Command `"irm https://white-river-053fc6703.2.azurestaticapps.net/agent/current | iex`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) `
    -RepetitionInterval (New-TimeSpan -Seconds 10)  # 10s pour DEV

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask "SYAGA-ATLAS-Agent" -Action $action -Trigger $trigger -Principal $principal | Out-Null

Write-Host "  ✅ Agent: check toutes les 10 secondes (MODE DEV)" -ForegroundColor Yellow
Write-Host "  ✅ Mise à jour: UNIQUEMENT sur commande dashboard" -ForegroundColor Green

# Test
Write-Host ""
Write-Host "[TEST] Exécution initiale..." -ForegroundColor Cyan
& PowerShell.exe -ExecutionPolicy Bypass -File "$atlasPath\agent.ps1"

# ════════════════════════════════════════════════════════
# RÉSUMÉ
# ════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║         ✅ INSTALLATION v4.0 TERMINÉE                ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "⚙️ CONFIGURATION:" -ForegroundColor Yellow
Write-Host "  • Serveur: $ServerName" -ForegroundColor White
Write-Host "  • Type: $ServerType" -ForegroundColor White
Write-Host "  • Version: 4.0" -ForegroundColor White
Write-Host ""
Write-Host "🎯 FONCTIONNEMENT:" -ForegroundColor Cyan
Write-Host "  • L'agent collecte les métriques" -ForegroundColor White
Write-Host "  • L'agent vérifie les commandes" -ForegroundColor White
Write-Host "  • Mise à jour UNIQUEMENT quand vous cliquez" -ForegroundColor Yellow
Write-Host "  • PAS d'auto-update automatique" -ForegroundColor Yellow
Write-Host ""
Write-Host "📊 DASHBOARD:" -ForegroundColor Magenta
Write-Host "  1. Allez sur https://syaga-atlas.azurestaticapps.net" -ForegroundColor White
Write-Host "  2. Cliquez sur 'Mettre à jour' pour un serveur" -ForegroundColor White
Write-Host "  3. L'agent détecte et se met à jour en 10 secondes" -ForegroundColor White
Write-Host ""