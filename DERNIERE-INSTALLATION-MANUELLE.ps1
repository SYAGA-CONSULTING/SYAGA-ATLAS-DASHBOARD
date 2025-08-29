# ============================================================
#  DERNIERE INSTALLATION MANUELLE - APRES PLUS JAMAIS !
#  Agent v5.6 avec auto-update 100% depuis le dashboard
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "   DERNIERE INSTALLATION MANUELLE D'ATLAS" -ForegroundColor Yellow
Write-Host "   Apres ca, TOUT se fera depuis le dashboard !" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""

# Verifier admin
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERREUR] Executez en tant qu'Administrateur" -ForegroundColor Red
    exit 1
}

$atlasPath = "C:\ATLAS"
$configFile = "$atlasPath\config.json"
$agentPath = "$atlasPath\Agent\ATLAS-Agent-Current.ps1"
$tempPath = "$env:TEMP\ATLAS-Agent-v5.6-FINAL.ps1"

Write-Host "[1/5] Recuperation du ClientSecret..." -ForegroundColor Cyan

$clientSecret = ""

# Recuperer depuis l'agent existant
if (Test-Path $agentPath) {
    $content = Get-Content $agentPath -Raw
    if ($content -match '\$Script:ClientSecret\s*=\s*"([^"]+)"') {
        $clientSecret = $matches[1]
        if ($clientSecret -and $clientSecret -ne "AJOUTER_LE_SECRET_ICI" -and $clientSecret -ne "") {
            Write-Host "  [OK] ClientSecret recupere" -ForegroundColor Green
        }
    }
}

# Ou depuis config.json
if (!$clientSecret -and (Test-Path $configFile)) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($config.ClientSecret) {
            $clientSecret = $config.ClientSecret
            Write-Host "  [OK] ClientSecret recupere depuis config" -ForegroundColor Green
        }
    } catch {}
}

if (!$clientSecret) {
    Write-Host "  [!] ClientSecret non trouve - a ajouter dans $configFile" -ForegroundColor Yellow
}

Write-Host "[2/5] Telechargement agent v5.6-FINAL..." -ForegroundColor Cyan

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://raw.githubusercontent.com/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/gh-pages/ATLAS-Agent-v5.6-FINAL.ps1"
    Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing
    Write-Host "  [OK] Agent telecharge" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] Telechargement impossible" -ForegroundColor Red
    exit 1
}

Write-Host "[3/5] Arret des anciennes versions..." -ForegroundColor Cyan

Get-ScheduledTask | Where-Object { $_.TaskName -like "*ATLAS*" } | ForEach-Object {
    Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
    Write-Host "  [OK] $($_.TaskName) arrete" -ForegroundColor Green
}

Write-Host "[4/5] Configuration..." -ForegroundColor Cyan

if ($clientSecret) {
    $configData = @{
        ClientId = "f66a8c6c-1037-41b8-be3c-4f6e67c1f49e"
        TenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
        ClientSecret = $clientSecret
        SiteUrl = "https://syagaconsulting.sharepoint.com/sites/SYAGA-Atlas"
    }
    
    if (!(Test-Path $atlasPath)) {
        New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null
    }
    
    $configData | ConvertTo-Json | Out-File -FilePath $configFile -Encoding UTF8
    Write-Host "  [OK] Configuration sauvegardee" -ForegroundColor Green
} else {
    Write-Host "  [!] Config sans ClientSecret" -ForegroundColor Yellow
}

Write-Host "[5/5] Installation v5.6-FINAL..." -ForegroundColor Cyan

& $tempPath -Action Installer

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "   INSTALLATION TERMINEE !" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "A partir de maintenant:" -ForegroundColor Cyan
Write-Host "  1. Allez sur le dashboard" -ForegroundColor White
Write-Host "  2. Cliquez sur 'Deployer vers tous les agents'" -ForegroundColor White
Write-Host "  3. L'agent se mettra a jour TOUT SEUL" -ForegroundColor White
Write-Host ""
Write-Host "Dashboard: https://white-river-053fc6703.2.azurestaticapps.net" -ForegroundColor Cyan
Write-Host ""

if (!$clientSecret) {
    Write-Host "[ACTION REQUISE]" -ForegroundColor Yellow
    Write-Host "  1. Ouvrir: $configFile" -ForegroundColor Yellow
    Write-Host "  2. Remplacer AJOUTER_LE_SECRET_ICI par le vrai secret" -ForegroundColor Yellow
    Write-Host "  3. Redemarrer la tache ATLAS-Agent-v5" -ForegroundColor Yellow
}

Remove-Item $tempPath -Force -ErrorAction SilentlyContinue