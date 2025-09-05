# FIX UPDATER - Installe directement v12.4
Write-Host "=== FIX UPDATER - Installation v12.4 ===" -ForegroundColor Cyan

$updaterUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v12.4.ps1"
$updaterPath = "C:\SYAGA-ATLAS\updater.ps1"

try {
    # Backup
    if (Test-Path $updaterPath) {
        Copy-Item $updaterPath "C:\SYAGA-ATLAS\updater_backup.ps1" -Force
        Write-Host "[OK] Backup créé" -ForegroundColor Green
    }
    
    # Télécharger nouvel updater
    Write-Host "Téléchargement updater v12.4..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing
    
    if (Test-Path $updaterPath) {
        Write-Host "[OK] Updater v12.4 installé" -ForegroundColor Green
        
        # Exécuter immédiatement pour installer agent v12.4
        Write-Host "Exécution de l'updater pour installer agent v12.4..." -ForegroundColor Yellow
        & $updaterPath
        
        Write-Host ""
        Write-Host "=== SUCCÈS ===" -ForegroundColor Green
        Write-Host "Updater v12.4 installé et exécuté" -ForegroundColor Green
        Write-Host "L'agent v12.4 devrait être installé maintenant" -ForegroundColor Green
    }
} catch {
    Write-Host "[ERREUR] $_" -ForegroundColor Red
}