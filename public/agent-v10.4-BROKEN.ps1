# ATLAS Agent v10.4 - VERSION VOLONTAIREMENT DÉFECTUEUSE POUR TEST ROLLBACK
$script:Version = "10.4"
$hostname = $env:COMPUTERNAME

Write-Host "Agent v10.4 - BROKEN VERSION FOR ROLLBACK TESTING" -ForegroundColor Red

# ERREUR VOLONTAIRE : Division par zéro
Write-Host "Tentative division par zéro..." -ForegroundColor Yellow
$result = 10 / 0

# ERREUR VOLONTAIRE : Fichier inexistant
Write-Host "Lecture fichier inexistant..." -ForegroundColor Yellow
$content = Get-Content "C:\FICHIER_INEXISTANT.txt"

# ERREUR VOLONTAIRE : Boucle infinie
Write-Host "Boucle infinie..." -ForegroundColor Yellow
while ($true) {
    Start-Sleep -Milliseconds 100
}

# Ce code ne sera jamais atteint à cause des erreurs ci-dessus
Write-Host "Agent v10.4 terminé" -ForegroundColor Green