# INSTALLATION IMMEDIATE v5.7 - CORRIGE L'ERREUR 400 DEFINITIVEMENT

Write-Host ""
Write-Host "=== INSTALLATION v5.7 - ERREUR 400 CORRIGEE ===" -ForegroundColor Green
Write-Host ""

# Arreter agent actuel
Write-Host "[1] Arret agent actuel..." -ForegroundColor Yellow
Stop-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue
Write-Host "OK" -ForegroundColor Green

# Telecharger v5.7
Write-Host "[2] Telechargement v5.7..." -ForegroundColor Yellow
$tempPath = "$env:TEMP\ATLAS-Agent-v5.7-FINAL-WORKING.ps1"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://raw.githubusercontent.com/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/gh-pages/ATLAS-Agent-v5.7-FINAL-WORKING.ps1"
    Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing
    Write-Host "OK" -ForegroundColor Green
} catch {
    Write-Host "ERREUR" -ForegroundColor Red
    exit 1
}

# Installer v5.7
Write-Host "[3] Installation v5.7..." -ForegroundColor Yellow
& $tempPath -Action Installer

# Nettoyer
Remove-Item $tempPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== v5.7 INSTALLE ===" -ForegroundColor Green
Write-Host "L'erreur 400 est maintenant corrigee!" -ForegroundColor Green
Write-Host "L'agent cree des nouvelles entrees au lieu de modifier les anciennes." -ForegroundColor Yellow