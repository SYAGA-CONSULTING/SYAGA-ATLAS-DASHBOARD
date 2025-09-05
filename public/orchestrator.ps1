# ════════════════════════════════════════════════════════════════════
# ATLAS ORCHESTRATOR - JAMAIS MODIFIÉ - LANCE LES VERSIONS
# ════════════════════════════════════════════════════════════════════
# CE FICHIER NE DOIT JAMAIS ÊTRE MODIFIÉ
# Il lit current-version.txt et lance la bonne version
# ════════════════════════════════════════════════════════════════════

$atlasPath = "C:\SYAGA-ATLAS"
$versionsPath = "$atlasPath\versions"
$currentVersionFile = "$atlasPath\current-version.txt"
$logFile = "$atlasPath\orchestrator.log"

function Write-OrchestratorLog {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] ORCHESTRATOR: $Message"
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    Write-Host $logEntry -ForegroundColor Cyan
}

Write-OrchestratorLog "════════════════════════════════════════"
Write-OrchestratorLog "ATLAS ORCHESTRATOR - Démarrage"
Write-OrchestratorLog "════════════════════════════════════════"

# Créer structure si nécessaire
if (!(Test-Path $versionsPath)) {
    New-Item -ItemType Directory -Path $versionsPath -Force | Out-Null
    Write-OrchestratorLog "Dossier versions créé"
}

# Lire version courante
$currentVersion = "18.0"  # Version par défaut
if (Test-Path $currentVersionFile) {
    $currentVersion = Get-Content $currentVersionFile -Raw
    $currentVersion = $currentVersion.Trim()
    Write-OrchestratorLog "Version courante: v$currentVersion"
} else {
    # Créer fichier avec version par défaut
    $currentVersion | Out-File $currentVersionFile -Encoding UTF8 -NoNewline
    Write-OrchestratorLog "Fichier current-version.txt créé avec v$currentVersion"
}

# Chercher le fichier agent de cette version
$agentFile = "$versionsPath\agent-v$currentVersion.ps1"

if (Test-Path $agentFile) {
    Write-OrchestratorLog "Lancement agent v$currentVersion"
    Write-OrchestratorLog "Fichier: $agentFile"
    
    try {
        # Lancer l'agent
        & $agentFile
        
        Write-OrchestratorLog "Agent v$currentVersion terminé avec succès"
    } catch {
        Write-OrchestratorLog "ERREUR agent v$currentVersion: $_"
        
        # Si erreur, essayer version de fallback
        $fallbackVersion = "10.3"
        $fallbackFile = "$versionsPath\agent-v$fallbackVersion.ps1"
        
        if (Test-Path $fallbackFile) {
            Write-OrchestratorLog "Tentative fallback vers v$fallbackVersion"
            & $fallbackFile
        }
    }
} else {
    Write-OrchestratorLog "ERREUR: Agent v$currentVersion introuvable!"
    Write-OrchestratorLog "Fichier attendu: $agentFile"
    
    # Télécharger version manquante
    Write-OrchestratorLog "Tentative téléchargement v$currentVersion..."
    
    try {
        $downloadUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$currentVersion.ps1"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $agentFile -UseBasicParsing
        
        if ((Get-Item $agentFile).Length -gt 1000) {
            Write-OrchestratorLog "Agent v$currentVersion téléchargé avec succès"
            
            # Relancer après téléchargement
            & $agentFile
        } else {
            Write-OrchestratorLog "Téléchargement échoué - fichier trop petit"
        }
    } catch {
        Write-OrchestratorLog "Impossible de télécharger: $_"
    }
}

Write-OrchestratorLog "════════════════════════════════════════"
Write-OrchestratorLog "ORCHESTRATOR terminé"
Write-OrchestratorLog "════════════════════════════════════════"