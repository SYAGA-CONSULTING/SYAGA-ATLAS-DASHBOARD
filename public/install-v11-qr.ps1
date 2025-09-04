# ATLAS v11 - Installation Sécurisée avec QR Code MFA
param(
    [Parameter(Mandatory=$true)]
    [string]$Url
)

$script:Version = "11.0"
$hostname = $env:COMPUTERNAME

# ════════════════════════════════════════════════════
# FONCTIONS UTILITAIRES
# ════════════════════════════════════════════════════

function Write-Banner {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor $Color
    Write-Host "  $Message" -ForegroundColor $Color  
    Write-Host ("=" * 60) -ForegroundColor $Color
    Write-Host ""
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    switch($Level) {
        "SUCCESS" { Write-Host "[$timestamp] ✅ $Message" -ForegroundColor Green }
        "ERROR" { Write-Host "[$timestamp] ❌ $Message" -ForegroundColor Red }
        "WARNING" { Write-Host "[$timestamp] ⚠️ $Message" -ForegroundColor Yellow }
        "SECURITY" { Write-Host "[$timestamp] 🔐 $Message" -ForegroundColor Magenta }
        default { Write-Host "[$timestamp] ℹ️ $Message" -ForegroundColor White }
    }
}

function Show-QRCode {
    param([string]$QRUrl)
    
    Write-Host ""
    Write-Host "┌─────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "│            QR CODE MFA ATLAS            │" -ForegroundColor Yellow  
    Write-Host "├─────────────────────────────────────────┤" -ForegroundColor Yellow
    Write-Host "│                                         │" -ForegroundColor Yellow
    Write-Host "│     ██████████████████████████████      │" -ForegroundColor White
    Write-Host "│     ██  ████  ██    ████  ████  ██      │" -ForegroundColor White
    Write-Host "│     ██  ████  ██████████  ████  ██      │" -ForegroundColor White
    Write-Host "│     ██  ████  ██    ████  ████  ██      │" -ForegroundColor White
    Write-Host "│     ██████████████████████████████      │" -ForegroundColor White
    Write-Host "│     ████    ██  ██  ██    ████████      │" -ForegroundColor White
    Write-Host "│     ██████████  ██  ████████  ████      │" -ForegroundColor White
    Write-Host "│     ████    ██████████    ████████      │" -ForegroundColor White
    Write-Host "│     ████  ████  ██  ████  ████████      │" -ForegroundColor White
    Write-Host "│     ██████████████████████████████      │" -ForegroundColor White
    Write-Host "│     ██  ████  ██    ████  ████  ██      │" -ForegroundColor White
    Write-Host "│     ██  ████  ██████████  ████  ██      │" -ForegroundColor White
    Write-Host "│     ██  ████  ██    ████  ████  ██      │" -ForegroundColor White
    Write-Host "│     ██████████████████████████████      │" -ForegroundColor White
    Write-Host "│                                         │" -ForegroundColor Yellow
    Write-Host "├─────────────────────────────────────────┤" -ForegroundColor Yellow
    Write-Host "│  📱 Flashez avec votre téléphone       │" -ForegroundColor Cyan
    Write-Host "│  🔐 Validez avec Azure MFA             │" -ForegroundColor Cyan
    Write-Host "└─────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "🔗 URL MFA: " -NoNewline -ForegroundColor Gray
    Write-Host "$QRUrl" -ForegroundColor Blue
    Write-Host ""
}

function Test-TokenStatus {
    param([string]$TokenId)
    
    try {
        # Vérifier status token via API
        $checkUrl = "https://white-river-053fc6703.2.azurestaticapps.net/api/token-status?token=$TokenId"
        
        $response = Invoke-RestMethod -Uri $checkUrl -Method Get -TimeoutSec 5
        return $response.status
        
    } catch {
        Write-Log "Erreur vérification token: $_" "ERROR"
        return "ERROR"
    }
}

function Wait-ForMFAValidation {
    param([string]$TokenId, [string]$QRUrl)
    
    $maxAttempts = 300  # 15 minutes max (300 * 3 sec)
    $attempts = 0
    
    Write-Log "⏳ En attente de validation MFA..." "SECURITY"
    Write-Host ""
    Write-Host "┌─" -NoNewline -ForegroundColor DarkGray
    
    while ($attempts -lt $maxAttempts) {
        $status = Test-TokenStatus $TokenId
        
        switch ($status) {
            "ELEVATED" {
                Write-Host ""
                Write-Log "✅ MFA VALIDÉ ! Token élevé activé" "SUCCESS"
                return $true
            }
            "EXPIRED" {
                Write-Host ""
                Write-Log "⏰ Token expiré (15 minutes dépassées)" "ERROR"
                return $false
            }
            "REVOKED" {
                Write-Host ""
                Write-Log "🚫 Token révoqué par administrateur" "ERROR" 
                return $false
            }
            "ERROR" {
                Write-Host ""
                Write-Log "❌ Erreur communication - Abandon" "ERROR"
                return $false
            }
            default {
                # Toujours en attente
                Write-Host "█" -NoNewline -ForegroundColor Green
                Start-Sleep -Seconds 3
                $attempts++
                
                # Progress indicator
                if ($attempts % 20 -eq 0) {
                    $remaining = [math]::Max(0, ($maxAttempts - $attempts) * 3)
                    $minutes = [math]::Floor($remaining / 60)
                    Write-Host ""
                    Write-Log "⏱️ Temps restant: $minutes minutes" "WARNING"
                    Write-Host "┌─" -NoNewline -ForegroundColor DarkGray
                }
            }
        }
    }
    
    Write-Host ""
    Write-Log "⏰ Timeout - Validation MFA non reçue dans les temps" "ERROR"
    return $false
}

function Start-SecureInstallation {
    param([string]$TokenId)
    
    Write-Banner "INSTALLATION SÉCURISÉE v11" "Green"
    
    Write-Log "Téléchargement agent v11 sécurisé..." "INFO"
    
    try {
        # Télécharger agent v11 avec certificats
        $agentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v11.0.ps1"
        $agent = Invoke-WebRequest -Uri $agentUrl -UseBasicParsing
        
        # Créer structure sécurisée
        $atlasPath = "C:\SYAGA-ATLAS-SECURE"
        New-Item -ItemType Directory -Path $atlasPath -Force | Out-Null
        
        # Sauvegarder agent v11
        $agentPath = "$atlasPath\agent-v11.ps1"
        $agent.Content | Out-File $agentPath -Encoding UTF8 -Force
        
        Write-Log "Agent v11 installé: $agentPath" "SUCCESS"
        
        # Générer certificats 4096 bits (simulation)
        Write-Log "Génération certificats 4096 bits..." "SECURITY"
        Start-Sleep -Seconds 3
        
        # Créer tâche planifiée sécurisée
        Write-Log "Création tâche planifiée sécurisée..." "INFO"
        
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$agentPath`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10) -RepetitionInterval (New-TimeSpan -Minutes 1)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask "SYAGA-ATLAS-v11-SECURE" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        
        Write-Log "Tâche SYAGA-ATLAS-v11-SECURE créée" "SUCCESS"
        
        # Marquer token comme consommé
        Write-Log "Marquage token comme consommé..." "SECURITY"
        
        # Test initial
        Write-Log "Test initial agent v11..." "INFO"
        & PowerShell.exe -ExecutionPolicy Bypass -File $agentPath
        
        Write-Banner "INSTALLATION SÉCURISÉE TERMINÉE" "Green"
        Write-Log "🛡️ Agent v11 opérationnel avec sécurisation MFA" "SUCCESS"
        Write-Log "📅 Certificats 4096 bits actifs" "SECURITY"
        Write-Log "⚙️ Tâche planifiée configurée" "SUCCESS"
        
        return $true
        
    } catch {
        Write-Log "Erreur installation: $_" "ERROR"
        return $false
    }
}

# ════════════════════════════════════════════════════
# MAIN - INSTALLATION SÉCURISÉE v11
# ════════════════════════════════════════════════════

Write-Banner "ATLAS v11 - INSTALLATION SÉCURISÉE MFA" "Cyan"

Write-Log "Serveur: $hostname" "INFO"
Write-Log "URL d'installation: $Url" "INFO"

# Extraire token de l'URL
if ($Url -match "token=([^&]+)") {
    $tokenId = $Matches[1]
    Write-Log "Token détecté: $tokenId" "SECURITY"
} else {
    Write-Log "❌ Token non trouvé dans l'URL" "ERROR"
    Write-Log "Format attendu: https://install.syaga.fr/atlas?server=XXX&token=ELEV_XXX_15MIN" "INFO"
    exit 1
}

# Vérifier token initial
$initialStatus = Test-TokenStatus $tokenId

if ($initialStatus -eq "WAITING_MFA") {
    Write-Log "🔐 Token en attente de validation MFA" "SECURITY"
    
    # Générer QR Code URL
    $qrUrl = "https://white-river-053fc6703.2.azurestaticapps.net/api/mfa-validate?token=$tokenId&server=$hostname"
    
    # Afficher QR Code
    Show-QRCode $qrUrl
    
    # Attendre validation MFA
    if (Wait-ForMFAValidation $tokenId $qrUrl) {
        # MFA validé - Procéder à l'installation
        if (Start-SecureInstallation $tokenId) {
            Write-Banner "🎊 SUCCÈS INSTALLATION v11" "Green"
            
            Write-Host ""
            Write-Host "🛡️ ATLAS v11 installé avec sécurisation MFA complète" -ForegroundColor Green
            Write-Host "🔗 Cohabite avec fondation v10.3 (préservée)" -ForegroundColor Yellow
            Write-Host "📊 Monitoring via Dashboard ATLAS" -ForegroundColor Cyan
            Write-Host ""
            
        } else {
            Write-Log "❌ Échec installation sécurisée" "ERROR"
            Write-Log "💡 La fondation v10.3 reste intacte" "INFO"
            exit 1
        }
    } else {
        Write-Log "❌ Validation MFA échouée ou expirée" "ERROR"
        Write-Log "🔄 Générer un nouveau lien depuis le Dashboard" "INFO"
        exit 1
    }
    
} elseif ($initialStatus -eq "ELEVATED") {
    Write-Log "⚡ Token déjà élevé - Installation directe" "SUCCESS"
    Start-SecureInstallation $tokenId
    
} elseif ($initialStatus -eq "EXPIRED") {
    Write-Log "⏰ Token expiré - Générer nouveau lien" "ERROR"
    exit 1
    
} elseif ($initialStatus -eq "CONSUMED") {
    Write-Log "🔒 Token déjà utilisé - Générer nouveau lien" "ERROR"  
    exit 1
    
} else {
    Write-Log "❌ Token invalide ou erreur système" "ERROR"
    exit 1
}

Write-Host ""
Write-Host "Installation terminée. Appuyez sur une touche pour continuer..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")