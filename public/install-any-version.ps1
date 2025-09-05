# ATLAS - GÉNÉRATEUR DE LIENS D'INSTALLATION
# Usage: .\install-any-version.ps1 -Version 13.0

param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

$baseUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public"
$atlasPath = "C:\SYAGA-ATLAS"

Write-Host ""
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " ATLAS INSTALLATION v$Version" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Créer le dossier si nécessaire
if (!(Test-Path $atlasPath)) {
    New-Item -Path $atlasPath -ItemType Directory -Force | Out-Null
    Write-Host "[OK] Dossier $atlasPath créé" -ForegroundColor Green
}

# Backup de l'agent actuel
$agentPath = "$atlasPath\agent.ps1"
if (Test-Path $agentPath) {
    $backupPath = "$atlasPath\agent_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
    Copy-Item $agentPath $backupPath -Force
    Write-Host "[OK] Backup créé: $backupPath" -ForegroundColor Green
}

# Télécharger et installer la version demandée
$agentUrl = "$baseUrl/agent-v$Version.ps1"
Write-Host "Téléchargement depuis: $agentUrl" -ForegroundColor Cyan

try {
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing
    
    if (Test-Path $agentPath) {
        # Vérifier que le fichier a bien été téléchargé
        $content = Get-Content $agentPath -First 5 | Out-String
        if ($content -match "ATLAS Agent v$Version") {
            Write-Host "[OK] Agent v$Version installé avec succès!" -ForegroundColor Green
            
            # Si v12.5 ou plus, installer aussi l'updater v12.4
            if ([version]$Version -ge [version]"12.5") {
                Write-Host ""
                Write-Host "Installation de l'updater v12.4..." -ForegroundColor Yellow
                $updaterUrl = "$baseUrl/updater-v12.4.ps1"
                $updaterPath = "$atlasPath\updater.ps1"
                
                try {
                    Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
                    Write-Host "[OK] Updater v12.4 installé" -ForegroundColor Green
                } catch {
                    Write-Host "[WARNING] Impossible d'installer l'updater: $_" -ForegroundColor Yellow
                }
            }
            
            # Relancer la tâche planifiée
            Write-Host ""
            Write-Host "Redémarrage de la tâche planifiée..." -ForegroundColor Yellow
            Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
            
            Write-Host "[OK] Agent v$Version actif!" -ForegroundColor Green
            Write-Host ""
            Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host " INSTALLATION RÉUSSIE - v$Version" -ForegroundColor Green
            Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan
            
        } else {
            Write-Host "[ERREUR] Le fichier téléchargé ne semble pas être l'agent v$Version" -ForegroundColor Red
            Write-Host "Contenu:" -ForegroundColor Yellow
            Write-Host $content
        }
    } else {
        Write-Host "[ERREUR] Le téléchargement a échoué" -ForegroundColor Red
    }
    
} catch {
    Write-Host "[ERREUR] $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "URL tentée: $agentUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Versions disponibles:" -ForegroundColor Cyan
    Write-Host "  - 10.3 (foundation)" -ForegroundColor White
    Write-Host "  - 12.2 (minimal)" -ForegroundColor White
    Write-Host "  - 12.4 (tracking)" -ForegroundColor White
    Write-Host "  - 12.5 (auto-fix)" -ForegroundColor White
    Write-Host "  - 12.6 (logs enrichis)" -ForegroundColor White
    Write-Host "  - 13.0 (rollback)" -ForegroundColor White
    Write-Host "  - 13.1-broken (test rollback)" -ForegroundColor White
    Write-Host "  - 14.0 (orchestration data)" -ForegroundColor White
    Write-Host "  - 15.0 (orchestration commands)" -ForegroundColor White
}

Write-Host ""