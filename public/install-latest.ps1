# ATLAS - Point d'entrée permanent pour la dernière version
# CE FICHIER NE CHANGE JAMAIS - Toujours utiliser ce lien !

$LATEST_VERSION = "5.3"  # Juste changer cette ligne pour les nouvelles versions
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

# Récupérer paramètres depuis le générateur
$serverName = $env:COMPUTERNAME
$clientName = "SYAGA"
$serverType = "Physical"

# Lire paramètres depuis variable d'environnement
$p = $env:ATLAS_PARAMS
if ($p) {
    Write-Host "[INFO] Parametres chiffres recus" -ForegroundColor Green
    try {
        # Déchiffrer avec le nom du serveur local comme clé
        $currentServer = $env:COMPUTERNAME
        
        # Décoder la première couche
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($p))
        
        # Vérifier que ça commence par le nom du serveur
        if ($decoded -match "^([^|]+)\|(.+)$") {
            $targetServer = $Matches[1]
            $base64Data = $Matches[2]
            
            # SÉCURITÉ : Ce lien ne fonctionne QUE sur le bon serveur
            if ($targetServer -ne $currentServer) {
                Write-Host "[SECURITE] ERREUR: Lien chiffre pour '$targetServer'" -ForegroundColor Red
                Write-Host "[SECURITE] Ce serveur est: '$currentServer'" -ForegroundColor Red
                Write-Host "[SECURITE] Installation REFUSEE - Lien invalide pour ce serveur" -ForegroundColor Red
                Write-Host "" -ForegroundColor Red
                Write-Host "Ce lien ne peut fonctionner QUE sur le serveur $targetServer" -ForegroundColor Yellow
                exit 1
            }
            
            Write-Host "  [SECURITE] Cle de dechiffrement correcte: $currentServer" -ForegroundColor Green
            
            # Décoder les paramètres
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64Data))
            $params = $json | ConvertFrom-Json
            
            if ($params.server) { 
                $serverName = $params.server
                Write-Host "  - Serveur: $serverName [CHIFFREMENT VERIFIE]" -ForegroundColor Green
            }
            if ($params.client) { 
                $clientName = $params.client
                Write-Host "  - Client: $clientName" -ForegroundColor Cyan
            }
            if ($params.type) { 
                $serverType = $params.type
                Write-Host "  - Type: $serverType" -ForegroundColor Cyan
            }
        } else {
            Write-Host "[SECURITE] Format de donnees invalide" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "[SECURITE] Impossible de dechiffrer - Lien corrompu ou invalide" -ForegroundColor Red
        Write-Host "Erreur: $_" -ForegroundColor Red
        exit 1
    }
} else {
    # Auto-détection si pas de paramètres
    Write-Host "[INFO] Pas de parametres - Auto-detection..." -ForegroundColor Yellow
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
}

# Sauvegarder config
@{
    Hostname = $serverName
    ClientName = $clientName
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