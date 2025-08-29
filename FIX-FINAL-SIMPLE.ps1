# FIX ULTRA SIMPLE - Juste remplacer l'agent sans complications

Write-Host "Fix simple en cours..." -ForegroundColor Green

# Arreter
Stop-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue

# Remplacer juste le fichier
$url = "https://raw.githubusercontent.com/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/gh-pages/ATLAS-Agent-v5.7-FINAL-WORKING.ps1"
$dest = "C:\ATLAS\Agent\ATLAS-Agent-Current.ps1"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing

Write-Host "Agent remplace" -ForegroundColor Green

# Redemarrer
Start-ScheduledTask -TaskName "ATLAS-Agent-v5" -ErrorAction SilentlyContinue

Write-Host "Agent redemarre" -ForegroundColor Green
Write-Host "Attendez 3 minutes et regardez les logs" -ForegroundColor Yellow