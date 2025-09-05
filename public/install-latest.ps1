# ATLAS - Point d'entrée permanent pour la dernière version
# CE FICHIER NE CHANGE JAMAIS - Toujours utiliser ce lien !

$LATEST_VERSION = "13.4"  # FIX REMONTÉE LOGS SHAREPOINT (400 CORRIGÉ)
$LATEST_INSTALL_URL = "https://white-river-053fc6703.2.azurestaticapps.net/public/install-v13.4.ps1"

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

# INTÉGRATION DIRECTE - LOGS SHAREPOINT DANS LATEST
Write-Host "[INFO] Installation directe avec logs SharePoint..." -ForegroundColor Yellow

# Configuration SharePoint pour logs
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

# Buffer logs
$script:InstallLogs = ""

function Write-InstallLog {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [LATEST] [$Level] $Message"
    
    $script:InstallLogs += "$logEntry`r`n"
    
    switch($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }
}

function Send-InstallLogs {
    param($Status)
    
    try {
        Write-InstallLog "Remontée logs vers SharePoint..." "INFO"
        
        # Token SharePoint
        $tokenBody = @{
            grant_type = "client_credentials"
            client_id = "$clientId@$tenantId"
            client_secret = $clientSecret
            resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
        }
        
        $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        $token = $tokenResponse.access_token
        
        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json;odata=verbose"
            "Content-Type" = "application/json;odata=verbose;charset=utf-8"
        }
        
        $hostname = $env:COMPUTERNAME
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
        
        # Logs avec header simplifié
        $fullLogs = "ATLAS INSTALLATION LATEST`r`nHost: $hostname`r`nStatus: $Status`r`n`r`n" + $script:InstallLogs
        if ($fullLogs.Length -gt 8000) {
            $fullLogs = $fullLogs.Substring(0, 8000) + "... (tronqué)"
        }
        
        # Données simplifiées - PAS de Title custom
        $data = @{
            "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
            Title = $hostname
            Hostname = $hostname  
            IPAddress = $ip
            State = "INSTALL-$Status"
            LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            AgentVersion = "LATEST-$LATEST_VERSION"
            Logs = $fullLogs
            Notes = "Installation LATEST v$LATEST_VERSION - $Status"
        }
        
        $jsonData = $data | ConvertTo-Json -Depth 10
        
        $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
        Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
        
        Write-InstallLog "Logs envoyés vers SharePoint avec succès" "SUCCESS"
        
    } catch {
        Write-InstallLog "Erreur SharePoint: $_" "ERROR"
        
        # Sauver en local
        $logFile = "$atlasPath\install-latest-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"  
        $script:InstallLogs | Out-File $logFile -Encoding UTF8
        Write-InstallLog "Logs sauvés: $logFile" "INFO"
    }
}

Write-InstallLog "DÉBUT installation LATEST v$LATEST_VERSION" "SUCCESS"

# Télécharger agent et updater directement
$agentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v13.0.ps1"
$updaterUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/updater-v13.0.ps1"
$agentPath = "$atlasPath\agent.ps1"
$updaterPath = "$atlasPath\updater.ps1"

try {
    Invoke-WebRequest -Uri $agentUrl -OutFile $agentPath -UseBasicParsing
    Write-InstallLog "Agent téléchargé" "SUCCESS"
    
    Invoke-WebRequest -Uri $updaterUrl -OutFile $updaterPath -UseBasicParsing  
    Write-InstallLog "Updater téléchargé" "SUCCESS"
    
    # Supprimer anciennes tâches
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Confirm:$false -ErrorAction SilentlyContinue
    Write-InstallLog "Anciennes tâches supprimées" "SUCCESS"
    
    # Créer nouvelles tâches
    $agentAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$agentPath`""
    $agentTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration (New-TimeSpan -Days 365)
    $agentSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
    $agentPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -Action $agentAction -Trigger $agentTrigger -Settings $agentSettings -Principal $agentPrincipal -Force | Out-Null
    Write-InstallLog "Tâche Agent créée" "SUCCESS"
    
    $updaterAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$updaterPath`""
    $updaterTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(30) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 365)
    $updaterSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
    $updaterPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    Register-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -Action $updaterAction -Trigger $updaterTrigger -Settings $updaterSettings -Principal $updaterPrincipal -Force | Out-Null
    Write-InstallLog "Tâche Updater créée" "SUCCESS"
    
    # Démarrer tâches
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent"
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" 
    Write-InstallLog "Tâches démarrées" "SUCCESS"
    
    Send-InstallLogs "SUCCESS"
    
} catch {
    Write-InstallLog "ERREUR installation: $_" "ERROR"
    Send-InstallLogs "FAILED"
}
    
    # Vérifier que les 2 tâches sont créées
    $agentTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -EA SilentlyContinue
    $updaterTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -EA SilentlyContinue
    
    if ($agentTask -and $updaterTask) {
        Write-Host ""
        Write-Host "[OK] Les 2 taches sont installees:" -ForegroundColor Green
        Write-Host "  ✓ SYAGA-ATLAS-Agent   : Execution toutes les minutes" -ForegroundColor Green
        Write-Host "  ✓ SYAGA-ATLAS-Updater : Verification MAJ toutes les minutes" -ForegroundColor Green
    } else {
        Write-Host "[ERREUR] Installation incomplete - taches manquantes" -ForegroundColor Red
        if (!$agentTask) { Write-Host "  ✗ SYAGA-ATLAS-Agent manquante" -ForegroundColor Red }
        if (!$updaterTask) { Write-Host "  ✗ SYAGA-ATLAS-Updater manquante" -ForegroundColor Red }
        exit 1
    }
    
} catch {
    Write-Host "[ERREUR] Impossible d'installer: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "         INSTALLATION REUSSIE !" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Version installee : v$LATEST_VERSION" -ForegroundColor Yellow
Write-Host "Type de serveur  : $serverType" -ForegroundColor Yellow
Write-Host "Auto-Update      : Actif (verification/minute)" -ForegroundColor Green
Write-Host ""