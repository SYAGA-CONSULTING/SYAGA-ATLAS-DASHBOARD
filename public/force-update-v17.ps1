# Script pour forcer la mise à jour vers v17.0 sur tous les serveurs ATLAS
# Ce script crée des commandes UPDATE dans SharePoint

$hostname = $env:COMPUTERNAME

# Configuration SharePoint
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))
$siteName = "syagacons"
$commandsListId = "a056e76f-7947-465c-8356-dc6e18098f76"

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  FORCE UPDATE ATLAS v17.0 - IA PRÉDICTIVE" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# Token SharePoint
Write-Host "[INFO] Connexion SharePoint..." -ForegroundColor Yellow
$tokenBody = @{
    grant_type = "client_credentials"
    client_id = "$clientId@$tenantId"
    client_secret = $clientSecret
    resource = "00000003-0000-0ff1-ce00-000000000000/${siteName}.sharepoint.com@$tenantId"
}

try {
    $tokenResponse = Invoke-RestMethod -Uri "https://accounts.accesscontrol.windows.net/$tenantId/tokens/OAuth/2" `
        -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
    
    $token = $tokenResponse.access_token
    Write-Host "[OK] Token obtenu" -ForegroundColor Green
    
    $headers = @{
        "Authorization" = "Bearer $token"
        "Accept" = "application/json;odata=verbose"
        "Content-Type" = "application/json;odata=verbose;charset=utf-8"
    }
    
    # Liste des serveurs à mettre à jour
    $servers = @(
        "SYAGA-HOST01",
        "SYAGA-HOST02",
        "SYAGA-VEEAM01"
    )
    
    Write-Host ""
    Write-Host "[INFO] Création des commandes UPDATE..." -ForegroundColor Yellow
    
    foreach ($server in $servers) {
        Write-Host "  • $server : " -NoNewline
        
        # Créer commande UPDATE
        $updateCommand = @{
            "__metadata" = @{ type = "SP.Data.ATLASCommandsListItem" }
            Title = "UPDATE"
            Target = $server
            Version = "17.0"
            Status = "PENDING"
            CreatedBy = "$hostname-FORCEUPDATE"
        } | ConvertTo-Json -Depth 10
        
        try {
            $createUrl = "https://${siteName}.sharepoint.com/_api/web/lists(guid'$commandsListId')/items"
            $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method POST -Body $updateCommand
            
            Write-Host "✅ UPDATE v17.0 créé (ID: $($response.d.Id))" -ForegroundColor Green
        } catch {
            Write-Host "❌ Erreur: $_" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "[INFO] Commandes créées avec succès !" -ForegroundColor Green
    Write-Host ""
    Write-Host "Les serveurs vont se mettre à jour dans la prochaine minute vers:" -ForegroundColor Cyan
    Write-Host "  • Agent v17.0 : IA prédictive & Machine Learning" -ForegroundColor White
    Write-Host "  • Updater v14.0 : Monitoring temps réel avancé" -ForegroundColor White
    Write-Host ""
    Write-Host "Nouvelles capacités:" -ForegroundColor Yellow
    Write-Host "  🤖 Prédiction de pannes avec ML" -ForegroundColor White
    Write-Host "  📈 Analyse de tendances (régression linéaire)" -ForegroundColor White
    Write-Host "  🔍 Détection d'anomalies automatique" -ForegroundColor White
    Write-Host "  🔧 Maintenance préventive intelligente" -ForegroundColor White
    Write-Host "  📊 Patterns cycliques et corrélations" -ForegroundColor White
    Write-Host "  🔄 Rollback automatique si problème (v16.0)" -ForegroundColor White
    Write-Host "  🩺 Diagnostics automatiques (v15.0)" -ForegroundColor White
    Write-Host "  📡 Monitoring services critiques (v14.0)" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host "[ERREUR] Impossible de créer les commandes: $_" -ForegroundColor Red
}

Write-Host "===================================================" -ForegroundColor Green
Write-Host "          COMMANDES UPDATE CRÉÉES !" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green