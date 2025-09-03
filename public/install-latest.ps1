# ATLAS - Point d'entrée permanent pour la dernière version
# CE FICHIER NE CHANGE JAMAIS - Toujours utiliser ce lien !

$LATEST_VERSION = "5.1"  # Juste changer cette ligne pour les nouvelles versions
$LATEST_URL = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$LATEST_VERSION.ps1"

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  ATLAS INSTALLER - Derniere version: v$LATEST_VERSION" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# Créer structure
$atlasPath = "C:\SYAGA-ATLAS"
New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null

# Détection du type de serveur
$serverType = "Physical"
$roles = Get-WindowsFeature | Where-Object { $_.Installed -eq $true }
if ($roles | Where-Object { $_.Name -eq "Hyper-V" }) {
    $serverType = "Host"
    Write-Host "[DETECT] Hyper-V detecte -> Type: Host" -ForegroundColor Green
} elseif ((Get-WmiObject -Class Win32_ComputerSystem).Model -match "Virtual") {
    $serverType = "VM"
    Write-Host "[DETECT] Machine virtuelle -> Type: VM" -ForegroundColor Green
} else {
    Write-Host "[DETECT] Machine physique -> Type: Physical" -ForegroundColor Yellow
}

# Sauvegarder config
@{
    Hostname = $env:COMPUTERNAME
    ClientName = "SYAGA"
    ServerType = $serverType
    InstallDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Version = $LATEST_VERSION
} | ConvertTo-Json | Out-File "$atlasPath\config.json" -Encoding UTF8

Write-Host "[OK] Configuration sauvegardee (Type: $serverType)" -ForegroundColor Green

# Télécharger la dernière version
Write-Host "[INFO] Telechargement agent v$LATEST_VERSION..." -ForegroundColor Yellow
try {
    $agent = Invoke-RestMethod -Uri $LATEST_URL
    $agent | Out-File "$atlasPath\agent.ps1" -Encoding UTF8 -Force
    Write-Host "[OK] Agent v$LATEST_VERSION installe" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Impossible de telecharger: $_" -ForegroundColor Red
    exit 1
}

# Créer/Recréer tâche planifiée
Write-Host "[INFO] Configuration tache planifiee..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -EA SilentlyContinue

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$atlasPath\agent.ps1`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask "SYAGA-ATLAS-Agent" -Action $action -Trigger $trigger -Principal $principal | Out-Null

Write-Host "[OK] Tache planifiee creee (execution/minute)" -ForegroundColor Green

# Test initial
Write-Host ""
Write-Host "[TEST] Execution initiale..." -ForegroundColor Cyan
& PowerShell.exe -ExecutionPolicy Bypass -File "$atlasPath\agent.ps1"

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "         INSTALLATION REUSSIE !" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Version installee : v$LATEST_VERSION" -ForegroundColor Yellow
Write-Host "Type de serveur  : $serverType" -ForegroundColor Yellow
Write-Host "Auto-Update      : Actif (verification/minute)" -ForegroundColor Green
Write-Host ""