# ════════════════════════════════════════════════════
# SCRIPT DIAGNOSTIC - ENVOI FORCÉ LOGS INSTALLATION
# ════════════════════════════════════════════════════

# Configuration SharePoint
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$serversListId = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

$hostname = $env:COMPUTERNAME
Write-Host "DIAGNOSTIC - Envoi forcé logs installation pour $hostname" -ForegroundColor Yellow

# Chercher le fichier log d'installation le plus récent
$logPattern = "C:\SYAGA-ATLAS\installation-v*.log"
$logFiles = Get-ChildItem $logPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

if ($logFiles.Count -eq 0) {
    Write-Host "ERREUR: Aucun fichier log d'installation trouvé" -ForegroundColor Red
    exit 1
}

$latestLogFile = $logFiles[0]
Write-Host "Fichier log trouvé : $($latestLogFile.FullName)" -ForegroundColor Green
Write-Host "Taille : $($latestLogFile.Length) bytes" -ForegroundColor Gray
Write-Host "Date : $($latestLogFile.LastWriteTime)" -ForegroundColor Gray

# Lire les logs
try {
    $logsContent = Get-Content $latestLogFile.FullName -Raw
    Write-Host "Logs lus avec succès ($($logsContent.Length) caractères)" -ForegroundColor Green
} catch {
    Write-Host "ERREUR lecture logs : $_" -ForegroundColor Red
    exit 1
}

# Token SharePoint
try {
    Write-Host "Obtention token SharePoint..." -ForegroundColor Yellow
    
    $tokenBody = @{
        grant_type = "client_credentials"
        client_id = "$clientId@$tenantId"
        client_secret = $clientSecret
        resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
    }
    
    $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
        -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
    
    $token = $tokenResponse.access_token
    Write-Host "Token obtenu avec succès" -ForegroundColor Green
    
} catch {
    Write-Host "ERREUR token SharePoint : $_" -ForegroundColor Red
    exit 1
}

# Préparer headers
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept" = "application/json;odata=verbose"
    "Content-Type" = "application/json;odata=verbose;charset=utf-8"
}

# Informations système
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch "Loopback"} | Select-Object -First 1).IPAddress
$currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# APPROCHE DIFFÉRENTE : Utiliser un Title unique avec timestamp
$uniqueTitle = "$hostname-LOG-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "Création entrée SharePoint avec Title : $uniqueTitle" -ForegroundColor Yellow

# Limiter les logs si trop volumineux
if ($logsContent.Length -gt 8000) {
    $logsContent = $logsContent.Substring(0, 8000) + "`r`n... (tronqué pour SharePoint)"
    Write-Host "Logs tronqués à 8000 caractères" -ForegroundColor Yellow
}

# Données simplifiées
$data = @{
    "__metadata" = @{ type = "SP.Data.ATLASServersListItem" }
    Title = $uniqueTitle
    Hostname = $hostname
    IPAddress = $ip
    State = "LOGS_INSTALL"
    LastContact = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    AgentVersion = "LOGS-v13.4"
    CPUUsage = 0
    MemoryUsage = 0
    DiskSpaceGB = 0
    Logs = $logsContent
    Notes = "Logs installation v13.4 - $currentTime - Envoi forcé"
}

$jsonData = $data | ConvertTo-Json -Depth 10

# Envoyer à SharePoint
try {
    Write-Host "Envoi vers SharePoint..." -ForegroundColor Yellow
    
    $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$serversListId')/items"
    $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $jsonData
    
    Write-Host "✅ SUCCÈS ! Logs d'installation envoyés vers SharePoint" -ForegroundColor Green
    Write-Host "Entrée créée avec ID : $($response.d.Id)" -ForegroundColor Green
    Write-Host "Title : $uniqueTitle" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ ERREUR envoi SharePoint : $_" -ForegroundColor Red
    
    # Afficher plus de détails sur l'erreur
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Réponse serveur : $responseBody" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "MAIS les logs sont disponibles dans le fichier local :" -ForegroundColor Yellow
    Write-Host $latestLogFile.FullName -ForegroundColor White
    
    exit 1
}

Write-Host ""
Write-Host "✅ DIAGNOSTIC TERMINÉ - Logs d'installation dans SharePoint !" -ForegroundColor Green