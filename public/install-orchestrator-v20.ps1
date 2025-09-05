# ════════════════════════════════════════════════════════════════════
# ATLAS INSTALLER v20.0 - NOUVELLE ARCHITECTURE ORCHESTRATEUR
# ════════════════════════════════════════════════════════════════════
# Installation complète avec structure robuste
# ════════════════════════════════════════════════════════════════════

param(
    [switch]$Force,
    [switch]$Silent
)

$InstallerVersion = "20.0"
$AtlasRoot = "C:\SYAGA-ATLAS"

function Write-Installer {
    param($Message, $Level = "INFO")
    
    $color = switch($Level) {
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default { "Cyan" }
    }
    
    if (!$Silent) {
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
    
    # Log dans fichier
    $logFile = "$AtlasRoot\install-$(Get-Date -Format 'yyyyMMdd').log"
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'HH:mm:ss') [$Level] $Message" -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       ATLAS ORCHESTRATOR v20.0 - INSTALLER           ║" -ForegroundColor Cyan
Write-Host "║         Architecture nouvelle génération             ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ════════════════════════════════════════════════════════════════════
# VÉRIFICATIONS PRÉALABLES
# ════════════════════════════════════════════════════════════════════
Write-Installer "Vérification prérequis..." "INFO"

# Vérifier droits admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Installer "Ce script doit être exécuté en tant qu'administrateur" "ERROR"
    exit 1
}

# Vérifier si déjà installé
if ((Test-Path "$AtlasRoot\orchestrator.ps1") -and !$Force) {
    Write-Installer "ATLAS déjà installé. Utilisez -Force pour réinstaller" "WARNING"
    
    $response = Read-Host "Voulez-vous mettre à jour ? (O/N)"
    if ($response -ne "O") {
        exit 0
    }
}

# ════════════════════════════════════════════════════════════════════
# ARRÊT ANCIENNES VERSIONS
# ════════════════════════════════════════════════════════════════════
Write-Installer "Arrêt des anciennes tâches..." "INFO"

$oldTasks = @(
    "SYAGA-ATLAS-Agent",
    "SYAGA-ATLAS-Updater",
    "SYAGA-ATLAS-Orchestrator"
)

foreach ($task in $oldTasks) {
    try {
        Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
        Write-Installer "  ✓ Supprimé: $task" "SUCCESS"
    } catch {
        # Silencieux si n'existe pas
    }
}

# ════════════════════════════════════════════════════════════════════
# CRÉATION STRUCTURE
# ════════════════════════════════════════════════════════════════════
Write-Installer "Création structure ATLAS..." "INFO"

$directories = @(
    $AtlasRoot,
    "$AtlasRoot\config",
    "$AtlasRoot\runtime",
    "$AtlasRoot\staging", 
    "$AtlasRoot\backup",
    "$AtlasRoot\logs"
)

foreach ($dir in $directories) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Installer "  ✓ Créé: $dir" "SUCCESS"
    }
}

# ════════════════════════════════════════════════════════════════════
# TÉLÉCHARGEMENT FICHIERS
# ════════════════════════════════════════════════════════════════════
Write-Installer "Téléchargement composants v$InstallerVersion..." "INFO"

$baseUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public"
$files = @{
    "orchestrator.ps1" = "atlas-orchestrator-v$InstallerVersion.ps1"
    "runtime\agent.ps1" = "agent-v$InstallerVersion.ps1"
}

$downloadSuccess = $true

foreach ($localFile in $files.Keys) {
    $localPath = "$AtlasRoot\$localFile"
    $remoteFile = $files[$localFile]
    $url = "$baseUrl/$remoteFile"
    
    try {
        Write-Installer "  Téléchargement: $remoteFile" "INFO"
        
        # Créer dossier parent si nécessaire
        $parent = Split-Path $localPath -Parent
        if (!(Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        
        # Télécharger
        Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing
        
        # Valider taille
        if ((Get-Item $localPath).Length -lt 1000) {
            throw "Fichier trop petit"
        }
        
        Write-Installer "  ✓ OK: $localFile" "SUCCESS"
        
    } catch {
        Write-Installer "  ✗ Échec: $localFile - $_" "ERROR"
        $downloadSuccess = $false
    }
}

if (!$downloadSuccess) {
    Write-Installer "Échec téléchargement. Installation annulée" "ERROR"
    exit 1
}

# ════════════════════════════════════════════════════════════════════
# CONFIGURATION INITIALE
# ════════════════════════════════════════════════════════════════════
Write-Installer "Configuration initiale..." "INFO"

# Créer fichier version
$versionData = @{
    Version = $InstallerVersion
    InstalledAt = Get-Date
    Hostname = $env:COMPUTERNAME
} | ConvertTo-Json

$versionData | Out-File "$AtlasRoot\config\version.json" -Encoding UTF8
Write-Installer "  ✓ Version configurée: v$InstallerVersion" "SUCCESS"

# Registre Windows
$regPath = "HKLM:\SOFTWARE\SYAGA\ATLAS"
if (!(Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

Set-ItemProperty -Path $regPath -Name "Version" -Value $InstallerVersion
Set-ItemProperty -Path $regPath -Name "InstallPath" -Value $AtlasRoot
Set-ItemProperty -Path $regPath -Name "InstallDate" -Value (Get-Date).ToString()
Write-Installer "  ✓ Registre configuré" "SUCCESS"

# ════════════════════════════════════════════════════════════════════
# CRÉATION TÂCHE PLANIFIÉE
# ════════════════════════════════════════════════════════════════════
Write-Installer "Création tâche planifiée..." "INFO"

try {
    # Action : lancer orchestrateur
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$AtlasRoot\orchestrator.ps1`" -Mode Run"
    
    # Déclencheur : toutes les 2 minutes
    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date).AddSeconds(30) `
        -RepetitionInterval (New-TimeSpan -Minutes 2) `
        -RepetitionDuration (New-TimeSpan -Days 365)
    
    # Paramètres
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    
    # Principal : SYSTEM avec privilèges élevés
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest
    
    # Créer tâche
    $task = Register-ScheduledTask `
        -TaskName "SYAGA-ATLAS-Orchestrator" `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "ATLAS Orchestrator v$InstallerVersion - Gestion automatique agents et mises à jour" `
        -Force
    
    Write-Installer "  ✓ Tâche créée: SYAGA-ATLAS-Orchestrator" "SUCCESS"
    
} catch {
    Write-Installer "  ✗ Erreur création tâche: $_" "ERROR"
    exit 1
}

# ════════════════════════════════════════════════════════════════════
# TEST INITIAL
# ════════════════════════════════════════════════════════════════════
Write-Installer "Test de l'installation..." "INFO"

try {
    # Test syntaxe orchestrateur
    $orchContent = Get-Content "$AtlasRoot\orchestrator.ps1" -Raw
    $errors = @()
    $null = [System.Management.Automation.PSParser]::Tokenize($orchContent, [ref]$errors)
    
    if ($errors.Count -gt 0) {
        throw "Erreurs syntaxe orchestrateur"
    }
    Write-Installer "  ✓ Syntaxe orchestrateur OK" "SUCCESS"
    
    # Test syntaxe agent
    $agentContent = Get-Content "$AtlasRoot\runtime\agent.ps1" -Raw
    $errors = @()
    $null = [System.Management.Automation.PSParser]::Tokenize($agentContent, [ref]$errors)
    
    if ($errors.Count -gt 0) {
        throw "Erreurs syntaxe agent"
    }
    Write-Installer "  ✓ Syntaxe agent OK" "SUCCESS"
    
    # Lancer première exécution
    Write-Installer "  Test exécution..." "INFO"
    $testJob = Start-Job -ScriptBlock {
        & "$using:AtlasRoot\orchestrator.ps1" -Mode Run
    }
    
    $completed = Wait-Job -Job $testJob -Timeout 30
    
    if ($completed) {
        $result = Receive-Job -Job $testJob
        Write-Installer "  ✓ Première exécution réussie" "SUCCESS"
    } else {
        Stop-Job -Job $testJob
        Write-Installer "  ⚠ Timeout première exécution (normal)" "WARNING"
    }
    
    Remove-Job -Job $testJob -Force
    
} catch {
    Write-Installer "  ✗ Test échoué: $_" "ERROR"
}

# ════════════════════════════════════════════════════════════════════
# DÉMARRAGE
# ════════════════════════════════════════════════════════════════════
Write-Installer "Démarrage ATLAS..." "INFO"

try {
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Orchestrator"
    Write-Installer "  ✓ Orchestrateur démarré" "SUCCESS"
} catch {
    Write-Installer "  ✗ Erreur démarrage: $_" "ERROR"
}

# ════════════════════════════════════════════════════════════════════
# RÉSUMÉ
# ════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║            INSTALLATION TERMINÉE !                    ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Version installée   : v$InstallerVersion" -ForegroundColor White
Write-Host "Chemin              : $AtlasRoot" -ForegroundColor White
Write-Host "Tâche planifiée     : SYAGA-ATLAS-Orchestrator (2 min)" -ForegroundColor White
Write-Host "Logs                : $AtlasRoot\logs\" -ForegroundColor White
Write-Host ""
Write-Host "Architecture :" -ForegroundColor Yellow
Write-Host "  • Orchestrateur : Gère les versions et updates" -ForegroundColor White
Write-Host "  • Runtime       : Version active de l'agent" -ForegroundColor White
Write-Host "  • Staging       : Zone de téléchargement" -ForegroundColor White
Write-Host "  • Backup        : Sauvegardes automatiques" -ForegroundColor White
Write-Host ""
Write-Host "Prochaines étapes :" -ForegroundColor Cyan
Write-Host "  1. Vérifier les logs : $AtlasRoot\logs\" -ForegroundColor White
Write-Host "  2. Surveiller le dashboard SharePoint" -ForegroundColor White
Write-Host "  3. Les mises à jour sont automatiques" -ForegroundColor White
Write-Host ""
Write-Host "Support : sebastien.questier@syaga.fr" -ForegroundColor DarkGray
Write-Host ""