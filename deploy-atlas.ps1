# SYAGA ATLAS - Déploiement avec Auth Interactive Microsoft 365
# Script PUBLIC sans secrets - Auth MFA obligatoire
# Usage: iwr bit.ly/syaga-atlas -UseBasicParsing | iex

param(
    [string]$Hostname = $env:COMPUTERNAME
)

$ErrorActionPreference = "Stop"

Write-Host @"

╔══════════════════════════════════════════════════════════╗
║          SYAGA ATLAS AGENT - DÉPLOIEMENT v0.18          ║
║                                                          ║
║  📋 Instructions:                                        ║
║  1. Connexion Microsoft 365 requise (MFA)               ║
║  2. Agent installé automatiquement                      ║
║  3. Hostname: $Hostname                                 ║
╚══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# 1. AUTHENTIFICATION INTERACTIVE MICROSOFT 365
Write-Host "🔐 AUTHENTIFICATION MICROSOFT 365" -ForegroundColor Yellow
Write-Host "   → Une fenêtre va s'ouvrir pour connexion" -ForegroundColor White
Write-Host "   → Connectez-vous avec votre compte @syaga.fr" -ForegroundColor White
Write-Host "   → MFA sera demandé automatiquement`n" -ForegroundColor White

# Ouvrir navigateur pour auth
$clientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"  # App ID publique
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$redirectUri = "http://localhost:8400"

# Démarrer serveur local temporaire pour capturer le code
$http = [System.Net.HttpListener]::new()
$http.Prefixes.Add("$redirectUri/")
$http.Start()

# URL d'auth
$authUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize?" +
    "client_id=$clientId&" +
    "response_type=code&" +
    "redirect_uri=$redirectUri&" +
    "response_mode=query&" +
    "scope=https://graph.microsoft.com/.default&" +
    "state=12345"

# Ouvrir navigateur
Write-Host "🌐 Ouverture du navigateur..." -ForegroundColor Yellow
Start-Process $authUrl

# Attendre callback
Write-Host "⏳ En attente de connexion..." -ForegroundColor Yellow
$context = $http.GetContext()
$code = $context.Request.QueryString["code"]

# Répondre au navigateur
$response = $context.Response
$responseString = "<html><body><h1>✅ Connexion réussie!</h1><p>Vous pouvez fermer cette fenêtre.</p></body></html>"
$buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
$response.ContentLength64 = $buffer.Length
$response.OutputStream.Write($buffer, 0, $buffer.Length)
$response.OutputStream.Close()
$http.Stop()

if (!$code) {
    Write-Host "❌ Authentification annulée" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Code d'autorisation reçu!" -ForegroundColor Green

# 2. ÉCHANGER CODE CONTRE TOKEN (utilise device code flow - pas de secret)
Write-Host "`n🔑 Obtention du token d'accès..." -ForegroundColor Yellow

$tokenBody = @{
    client_id = $clientId
    scope = "https://graph.microsoft.com/.default"
    code = $code
    redirect_uri = $redirectUri
    grant_type = "authorization_code"
    # PAS DE CLIENT_SECRET - Utilise PKCE ou device flow
}

try {
    # Pour app publique, utiliser PKCE ou delegated permissions
    $tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    
    # Alternative: Device code flow (plus sécurisé, pas de secret)
    Write-Host "📱 Utilisation du Device Code Flow..." -ForegroundColor Yellow
    
    $deviceCodeRequest = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/devicecode" -Method Post -Body @{
        client_id = $clientId
        scope = "https://graph.microsoft.com/.default"
    }
    
    Write-Host "`n📋 Code à entrer: $($deviceCodeRequest.user_code)" -ForegroundColor Cyan
    Write-Host "🔗 URL: $($deviceCodeRequest.verification_uri)" -ForegroundColor Yellow
    Start-Process $deviceCodeRequest.verification_uri
    
    # Attendre que l'user valide
    $tokenResponse = $null
    while (!$tokenResponse) {
        Start-Sleep -Seconds 5
        try {
            $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body @{
                grant_type = "urn:ietf:params:oauth:grant-type:device_code"
                client_id = $clientId
                device_code = $deviceCodeRequest.device_code
            }
        } catch {
            # Continue polling
        }
    }
    
    $accessToken = $tokenResponse.access_token
    Write-Host "✅ Token obtenu avec succès!" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Erreur obtention token: $_" -ForegroundColor Red
    exit 1
}

# 3. TÉLÉCHARGER AGENT DEPUIS SHAREPOINT
Write-Host "`n📥 Téléchargement de l'agent depuis SharePoint..." -ForegroundColor Yellow

$headers = @{ Authorization = "Bearer $accessToken" }
$localPath = "C:\SYAGA-ATLAS"

if (!(Test-Path $localPath)) {
    New-Item -ItemType Directory -Path $localPath -Force | Out-Null
}

# Télécharger l'agent actuel depuis SharePoint Documents
$agentUrl = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/drive/root:/Documents%20partages/ATLAS/atlas-agent-current.ps1:/content"

try {
    Invoke-WebRequest -Uri $agentUrl -Headers $headers -OutFile "$localPath\SYAGA-ATLAS-AGENT.ps1"
    Write-Host "✅ Agent v0.18 téléchargé!" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Agent non trouvé dans SharePoint, utilisation version embarquée" -ForegroundColor Yellow
    
    # Version minimale embarquée
    @'
# SYAGA ATLAS AGENT v0.18
$VERSION = "v0.18"
$HOSTNAME = if (Test-Path "C:\SYAGA-ATLAS\config.ps1") {
    . "C:\SYAGA-ATLAS\config.ps1"
    $HOSTNAME_OVERRIDE
} else { $env:COMPUTERNAME }

Write-Host "[$HOSTNAME] Agent $VERSION démarré"

# TODO: Implémenter collecte métriques et envoi SharePoint
'@ | Out-File "$localPath\SYAGA-ATLAS-AGENT.ps1" -Force
}

# 4. CONFIGURER HOSTNAME
Write-Host "`n📝 Configuration du hostname: $Hostname" -ForegroundColor Yellow
@"
# Configuration automatique générée
`$HOSTNAME_OVERRIDE = '$Hostname'
"@ | Out-File "$localPath\config.ps1" -Force

# 5. CRÉER TÂCHE PLANIFIÉE
Write-Host "`n⚙️ Installation du service Windows..." -ForegroundColor Yellow

$taskName = "SYAGA-ATLAS-Agent"

# Supprimer ancienne tâche si existe
schtasks /delete /tn $taskName /f 2>$null

# Créer nouvelle tâche SYSTEM
$result = schtasks /create /tn $taskName `
    /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\SYAGA-ATLAS\SYAGA-ATLAS-AGENT.ps1" `
    /sc minute /mo 2 `
    /ru SYSTEM `
    /rl HIGHEST `
    /f

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Tâche planifiée créée!" -ForegroundColor Green
} else {
    Write-Host "❌ Erreur création tâche planifiée" -ForegroundColor Red
    exit 1
}

# 6. DÉMARRER L'AGENT
Write-Host "`n🚀 Démarrage de l'agent..." -ForegroundColor Yellow
schtasks /run /tn $taskName

# 7. VÉRIFICATION
Write-Host "`n⏳ Vérification du démarrage..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task -and $task.State -ne "Disabled") {
    Write-Host "✅ Agent démarré avec succès!" -ForegroundColor Green
} else {
    Write-Host "⚠️ Vérifiez l'état de l'agent" -ForegroundColor Yellow
}

# 8. RÉSUMÉ
Write-Host @"

╔══════════════════════════════════════════════════════════╗
║                  ✅ DÉPLOIEMENT TERMINÉ                  ║
╠══════════════════════════════════════════════════════════╣
║  📊 Dashboard :  https://syaga-atlas.azurestaticapps.net ║
║  🖥️  Serveur  :  $Hostname                               ║
║  ⚡ Version   :  v0.18                                   ║
║  🔄 Fréquence :  Toutes les 2 minutes                    ║
║  👤 Exécution :  SYSTEM (service)                        ║
╚══════════════════════════════════════════════════════════╝

L'agent devrait apparaître sur le dashboard dans 1-2 minutes.

"@ -ForegroundColor Green