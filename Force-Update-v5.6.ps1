# Script rapide pour forcer la mise à jour vers v5.6 corrigé
# A exécuter UNE SEULE FOIS sur les serveurs avec erreur 400

Write-Host "Force update vers v5.6 corrigé..." -ForegroundColor Cyan

# Télécharger la version corrigée
$url = "https://raw.githubusercontent.com/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/gh-pages/ATLAS-Agent-v5.6-FINAL.ps1"
$dest = "C:\ATLAS\Agent\ATLAS-Agent-Current.ps1"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    Write-Host "✓ Agent mis à jour" -ForegroundColor Green
    
    # Redémarrer la tâche
    Restart-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
    Write-Host "✓ Tâche redémarrée" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "L'agent v5.6 corrigé est maintenant actif !" -ForegroundColor Green
    Write-Host "Les prochaines mises à jour se feront depuis le dashboard." -ForegroundColor Yellow
    
} catch {
    Write-Host "Erreur: $_" -ForegroundColor Red
}