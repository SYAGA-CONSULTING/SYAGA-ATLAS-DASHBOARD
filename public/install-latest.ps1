# ATLAS - Point d'entrée permanent pour la dernière version
# CE FICHIER NE CHANGE JAMAIS - Toujours utiliser ce lien !

$LATEST_VERSION = "5.1"  # Juste changer cette ligne pour les nouvelles versions
$LATEST_URL = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v$LATEST_VERSION.ps1"

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  ATLAS INSTALLER - Derniere version: v$LATEST_VERSION" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# SÉCURITÉ : Token temporaire de 15 minutes
$tokenFile = "C:\Windows\Temp\atlas_install_token.txt"
if (Test-Path $tokenFile) {
    $tokenData = Get-Content $tokenFile | ConvertFrom-Json
    $tokenAge = (Get-Date) - [DateTime]$tokenData.Created
    if ($tokenAge.TotalMinutes -lt 15) {
        Write-Host "[OK] Token valide encore $([math]::Round(15 - $tokenAge.TotalMinutes, 1)) minutes" -ForegroundColor Green
    } else {
        Write-Host "[SECURITE] Token expire - Installation refusee" -ForegroundColor Red
        Write-Host "Veuillez regenerer un nouveau lien depuis le dashboard" -ForegroundColor Yellow
        Remove-Item $tokenFile -Force
        exit 1
    }
} else {
    # Créer token pour 15 minutes
    @{
        Created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        ValidUntil = (Get-Date).AddMinutes(15).ToString("yyyy-MM-dd HH:mm:ss")
        Type = "Installation"
    } | ConvertTo-Json | Out-File $tokenFile -Force
    Write-Host "[SECURITE] Token cree - Valable 15 minutes" -ForegroundColor Yellow
}

# AUTO-SUPPRESSION après 15 minutes
$cleanupTask = @"
Start-Sleep -Seconds 900
if (Test-Path '$tokenFile') { Remove-Item '$tokenFile' -Force }
if (Test-Path '$($MyInvocation.MyCommand.Path)') { Remove-Item '$($MyInvocation.MyCommand.Path)' -Force }
"@
Start-Job -ScriptBlock ([ScriptBlock]::Create($cleanupTask)) | Out-Null
Write-Host "[SECURITE] Auto-nettoyage programme dans 15 minutes" -ForegroundColor DarkGray

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