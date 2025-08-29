# Script de migration vers ATLAS Agent v5.5 avec Auto-Update
# Ce script installe la nouvelle version sur les agents existants

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  MIGRATION VERS ATLAS v5.5 AUTOUPDATE" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier les droits admin
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERREUR: Ce script doit être exécuté en tant qu'Administrateur" -ForegroundColor Red
    exit 1
}

# Configuration
$atlasPath = "C:\ATLAS"
$configFile = "$atlasPath\config.json"
$agentPath = "$atlasPath\Agent\ATLAS-Agent-Current.ps1"
$tempPath = "$env:TEMP\ATLAS-Agent-v5.5-AUTOUPDATE.ps1"

Write-Host "[1/6] Vérification de l'installation existante..." -ForegroundColor Yellow

# Vérifier si ATLAS est installé
if (!(Test-Path $atlasPath)) {
    Write-Host "  ⚠️ ATLAS n'est pas installé. Installation complète requise." -ForegroundColor Yellow
    $install = Read-Host "  Voulez-vous installer ATLAS v5.5? (O/N)"
    if ($install -ne "O") {
        Write-Host "Installation annulée" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ✅ Installation ATLAS détectée" -ForegroundColor Green
}

Write-Host "[2/6] Récupération du ClientSecret existant..." -ForegroundColor Yellow

$clientSecret = ""

# Essayer de récupérer le secret depuis l'agent existant
if (Test-Path $agentPath) {
    $existingContent = Get-Content $agentPath -Raw
    if ($existingContent -match '\$Script:ClientSecret\s*=\s*"([^"]+)"') {
        $clientSecret = $matches[1]
        if ($clientSecret -and $clientSecret -ne "REMPLACER_PAR_LE_SECRET" -and $clientSecret -ne "") {
            Write-Host "  ✅ ClientSecret récupéré depuis l'agent existant" -ForegroundColor Green
        }
    }
}

# Ou depuis le fichier config existant
if (!$clientSecret -and (Test-Path $configFile)) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($config.ClientSecret -and $config.ClientSecret -ne "REMPLACER_PAR_LE_SECRET") {
            $clientSecret = $config.ClientSecret
            Write-Host "  ✅ ClientSecret récupéré depuis config.json" -ForegroundColor Green
        }
    } catch {}
}

if (!$clientSecret) {
    Write-Host "  ⚠️ ClientSecret non trouvé" -ForegroundColor Yellow
    Write-Host "  Le secret devra être ajouté manuellement dans $configFile" -ForegroundColor Yellow
}

Write-Host "[3/6] Téléchargement de l'agent v5.5..." -ForegroundColor Yellow

try {
    # Télécharger depuis GitHub
    $downloadUrl = "https://raw.githubusercontent.com/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/gh-pages/ATLAS-Agent-v5.5-AUTOUPDATE.ps1"
    
    # Utiliser Invoke-WebRequest avec TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing
    
    if (Test-Path $tempPath) {
        Write-Host "  ✅ Agent v5.5 téléchargé avec succès" -ForegroundColor Green
    } else {
        throw "Échec du téléchargement"
    }
} catch {
    Write-Host "  ❌ Erreur téléchargement: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[4/6] Arrêt de l'agent existant..." -ForegroundColor Yellow

# Arrêter les tâches planifiées existantes
Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
    try {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Write-Host "  ✅ Tâche arrêtée: $($_.TaskName)" -ForegroundColor Green
    } catch {}
}

Write-Host "[5/6] Configuration du ClientSecret..." -ForegroundColor Yellow

# Créer le fichier config.json si nécessaire
if ($clientSecret) {
    $configData = @{
        ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
        TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        ClientSecret = $clientSecret
        SiteUrl = "https://syagaconsulting.sharepoint.com/sites/SYAGA-Atlas"
    }
    
    # Créer le répertoire si nécessaire
    if (!(Test-Path $atlasPath)) {
        New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null
    }
    
    # Sauvegarder la configuration
    $configData | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8
    Write-Host "  ✅ Configuration sauvegardée dans $configFile" -ForegroundColor Green
} else {
    Write-Host "  ⚠️ Configuration créée sans ClientSecret" -ForegroundColor Yellow
    Write-Host "  IMPORTANT: Ajouter le ClientSecret dans $configFile" -ForegroundColor Red
    
    # Créer un fichier config par défaut
    $configData = @{
        ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
        TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        ClientSecret = "REMPLACER_PAR_LE_SECRET"
        SiteUrl = "https://syagaconsulting.sharepoint.com/sites/SYAGA-Atlas"
    }
    $configData | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8
}

Write-Host "[6/6] Installation de l'agent v5.5..." -ForegroundColor Yellow

try {
    # Lancer l'installation
    & $tempPath -Action Installer
    
    Write-Host ""
    Write-Host "======================================" -ForegroundColor Green
    Write-Host "  ✅ MIGRATION TERMINÉE AVEC SUCCÈS!" -ForegroundColor Green
    Write-Host "======================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Agent v5.5 installé avec:" -ForegroundColor Cyan
    Write-Host "  • Auto-update automatique toutes les 3 minutes" -ForegroundColor White
    Write-Host "  • Métriques enrichies (Services, Events, Veeam, Hyper-V)" -ForegroundColor White
    Write-Host "  • Configuration dans: $configFile" -ForegroundColor White
    Write-Host ""
    
    if (!$clientSecret) {
        Write-Host "⚠️ ACTION REQUISE:" -ForegroundColor Yellow
        Write-Host "  1. Ouvrir $configFile" -ForegroundColor Yellow
        Write-Host "  2. Remplacer 'REMPLACER_PAR_LE_SECRET' par le vrai ClientSecret" -ForegroundColor Yellow
        Write-Host "  3. Redémarrer la tâche ATLAS-Agent-v5" -ForegroundColor Yellow
    } else {
        Write-Host "✅ L'agent est opérationnel et enverra ses métriques toutes les 3 minutes" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Dashboard: https://white-river-053fc6703.2.azurestaticapps.net" -ForegroundColor Cyan
    
} catch {
    Write-Host "  ❌ Erreur installation: $_" -ForegroundColor Red
    exit 1
} finally {
    # Nettoyer le fichier temporaire
    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
}