# SYAGA ATLAS AGENT v0.19 - Auth Interactive Une Fois + DPAPI
# Déployable via OneDrive sans secrets

param(
    [string]$Action = "Run",
    [string]$Hostname = $env:COMPUTERNAME
)

$VERSION = "v0.19"
$ATLAS_PATH = "C:\SYAGA-ATLAS"
$AUTH_FILE = "$ATLAS_PATH\auth.secure"
$CONFIG_FILE = "$ATLAS_PATH\config.json"

# Créer dossier si nécessaire
if (!(Test-Path $ATLAS_PATH)) {
    New-Item -ItemType Directory -Path $ATLAS_PATH -Force | Out-Null
}

# ============ INSTALLATION INITIALE ============
if ($Action -eq "Install") {
    Write-Host @"
╔════════════════════════════════════════════════════╗
║      SYAGA ATLAS AGENT v0.19 - INSTALLATION       ║
║               Hostname: $Hostname                  ║
╚════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    # Sauvegarder config
    @{
        hostname = $Hostname
        version = $VERSION
        installed = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json | Out-File $CONFIG_FILE -Force

    # Créer tâche planifiée
    Write-Host "`n⚙️ Création service Windows..." -ForegroundColor Yellow
    
    $taskName = "SYAGA-ATLAS-Agent"
    schtasks /delete /tn $taskName /f 2>$null
    
    $scriptContent = (Get-Content $MyInvocation.MyCommand.Path -Raw)
    $scriptContent | Out-File "$ATLAS_PATH\agent.ps1" -Force
    
    schtasks /create /tn $taskName `
        /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File $ATLAS_PATH\agent.ps1" `
        /sc minute /mo 2 /ru SYSTEM /rl HIGHEST /f | Out-Null
    
    Write-Host "✅ Service installé" -ForegroundColor Green
    
    # Première exécution pour auth
    Write-Host "`n🔐 Configuration authentification (une seule fois)..." -ForegroundColor Yellow
    & "$ATLAS_PATH\agent.ps1"
    
    Write-Host @"
    
✅ INSTALLATION TERMINÉE!
════════════════════════
📊 Dashboard: https://syaga-atlas.azurestaticapps.net
🖥️ Serveur: $Hostname
⚡ Version: v0.19
🔄 Fréquence: 2 minutes
🔐 Auth: Configurée pour 90 jours

"@ -ForegroundColor Green
    
    exit
}

# ============ GESTION AUTHENTIFICATION ============
function Get-StoredAuth {
    if (Test-Path $AUTH_FILE) {
        try {
            $encrypted = Get-Content $AUTH_FILE
            $secure = ConvertTo-SecureString $encrypted
            $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            $json = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
            return $json | ConvertFrom-Json
        } catch {
            Write-Host "⚠️ Auth corrompue, re-configuration nécessaire" -ForegroundColor Yellow
            Remove-Item $AUTH_FILE -Force
        }
    }
    return $null
}

function Save-Auth($refreshToken) {
    $authData = @{
        refreshToken = $refreshToken
        expires = (Get-Date).AddDays(90).ToString("yyyy-MM-dd")
        hostname = $Hostname
    }
    
    $json = $authData | ConvertTo-Json
    $secure = ConvertTo-SecureString $json -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString $secure
    $encrypted | Out-File $AUTH_FILE -Force
    
    Write-Host "✅ Authentification sauvegardée (valide 90 jours)" -ForegroundColor Green
}

function Get-InteractiveAuth {
    Write-Host @"

╔════════════════════════════════════════════════════╗
║         CONFIGURATION INITIALE REQUISE            ║
║         (Une seule fois par machine)              ║
╚════════════════════════════════════════════════════╝

"@ -ForegroundColor Yellow

    Write-Host "📋 Instructions:" -ForegroundColor Cyan
    Write-Host "1. Une fenêtre va s'ouvrir" -ForegroundColor White
    Write-Host "2. Connectez-vous avec votre compte @syaga.fr" -ForegroundColor White
    Write-Host "3. Copiez le code affiché après connexion" -ForegroundColor White
    Write-Host ""

    # Device code flow (pas de secret requis)
    $deviceCodeUrl = "https://login.microsoftonline.com/6027d81c-ad9b-48f5-9da6-96f1bad11429/oauth2/v2.0/devicecode"
    $body = @{
        client_id = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
        scope = "https://graph.microsoft.com/.default offline_access"
    }
    
    $response = Invoke-RestMethod -Uri $deviceCodeUrl -Method Post -Body $body
    
    Write-Host "🔑 CODE À ENTRER: " -NoNewline -ForegroundColor Cyan
    Write-Host $response.user_code -ForegroundColor Yellow
    Write-Host ""
    
    # Ouvrir navigateur
    Start-Process $response.verification_uri
    
    Write-Host "⏳ En attente de connexion..." -ForegroundColor Yellow
    
    # Attendre validation
    $tokenUrl = "https://login.microsoftonline.com/6027d81c-ad9b-48f5-9da6-96f1bad11429/oauth2/v2.0/token"
    $tokenBody = @{
        grant_type = "urn:ietf:params:oauth:grant-type:device_code"
        client_id = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
        device_code = $response.device_code
    }
    
    $elapsed = 0
    while ($elapsed -lt $response.expires_in) {
        Start-Sleep -Seconds 5
        $elapsed += 5
        
        try {
            $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody
            Write-Host "✅ Connexion réussie!" -ForegroundColor Green
            return $tokenResponse.refresh_token
        } catch {
            # Continue polling
            Write-Host "." -NoNewline
        }
    }
    
    throw "Timeout authentification"
}

function Get-AccessToken($refreshToken) {
    $tokenUrl = "https://login.microsoftonline.com/6027d81c-ad9b-48f5-9da6-96f1bad11429/oauth2/v2.0/token"
    $body = @{
        client_id = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
        grant_type = "refresh_token"
        refresh_token = $refreshToken
        scope = "https://graph.microsoft.com/.default"
    }
    
    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body
    return $response.access_token
}

# ============ COLLECTE MÉTRIQUES ============
function Collect-Metrics {
    $metrics = @{
        Hostname = $Hostname
        AgentVersion = $VERSION
        LastContact = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        State = "OK"
    }
    
    # CPU
    try {
        $cpu = Get-Counter -Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 3
        $metrics.CPUUsage = [Math]::Round(($cpu.CounterSamples | Measure-Object CookedValue -Average).Average, 1)
    } catch { $metrics.CPUUsage = 0 }
    
    # RAM
    try {
        $os = Get-WmiObject Win32_OperatingSystem
        $metrics.MemoryUsage = [Math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
    } catch { $metrics.MemoryUsage = 0 }
    
    # Disk
    try {
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
        $metrics.DiskSpaceGB = [Math]::Round($disk.FreeSpace / 1GB, 1)
    } catch { $metrics.DiskSpaceGB = 0 }
    
    # Veeam
    $veeamService = Get-Service -Name "Veeam*" -ErrorAction SilentlyContinue
    $metrics.VeeamStatus = if ($veeamService) { "Installed" } else { "NotInstalled" }
    
    # IP
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"})[0].IPAddress
        $metrics.HyperVStatus = $ip
    } catch { $metrics.HyperVStatus = "Unknown" }
    
    return $metrics
}

# ============ ENVOI SHAREPOINT ============
function Send-ToSharePoint($metrics, $accessToken) {
    $headers = @{
        Authorization = "Bearer $accessToken"
        "Content-Type" = "application/json"
    }
    
    $listUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/lists/94dc7ad4-740f-4c1f-b99c-107e01c8f70b/items"
    
    # Chercher item existant
    $searchUrl = "$listUrl`?`$expand=fields"
    $existing = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method Get
    $item = $existing.value | Where-Object { $_.fields.Hostname -eq $metrics.Hostname }
    
    $body = @{ fields = $metrics } | ConvertTo-Json
    
    if ($item) {
        # Update
        $updateUrl = "$listUrl/$($item.id)"
        Invoke-RestMethod -Uri $updateUrl -Headers $headers -Method PATCH -Body $body | Out-Null
    } else {
        # Create
        $metrics.Title = $metrics.Hostname
        $body = @{ fields = $metrics } | ConvertTo-Json
        Invoke-RestMethod -Uri $listUrl -Headers $headers -Method POST -Body $body | Out-Null
    }
}

# ============ EXECUTION PRINCIPALE ============
try {
    # Vérifier/Obtenir auth
    $auth = Get-StoredAuth
    
    if (!$auth -or (Get-Date) -gt [DateTime]::Parse($auth.expires)) {
        Write-Host "🔐 Authentification requise..." -ForegroundColor Yellow
        $refreshToken = Get-InteractiveAuth
        Save-Auth $refreshToken
        $auth = Get-StoredAuth
    }
    
    # Obtenir access token
    $accessToken = Get-AccessToken $auth.refreshToken
    
    # Collecter métriques
    $metrics = Collect-Metrics
    
    # Envoyer à SharePoint
    Send-ToSharePoint $metrics $accessToken
    
    Write-Host "[$Hostname] v0.19 - CPU:$($metrics.CPUUsage)% RAM:$($metrics.MemoryUsage)% Disk:$($metrics.DiskSpaceGB)GB"
    
} catch {
    Write-Host "❌ Erreur: $_" -ForegroundColor Red
    
    # Si erreur auth, supprimer pour forcer re-config
    if ($_ -like "*401*" -or $_ -like "*refresh*") {
        Remove-Item $AUTH_FILE -Force -ErrorAction SilentlyContinue
        Write-Host "⚠️ Auth supprimée, re-configuration au prochain lancement" -ForegroundColor Yellow
    }
}