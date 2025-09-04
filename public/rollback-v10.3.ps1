# ATLAS ROLLBACK v10.3 - RETOUR FONDATION ABSOLUE
$script:Version = "10.3"
$hostname = $env:COMPUTERNAME
$logFile = "C:\SYAGA-ATLAS\rollback_log.txt"

# ════════════════════════════════════════════════════
# SHAREPOINT CONFIG
# ════════════════════════════════════════════════════
$tenantId = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
$clientId = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
$clientSecretB64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
$clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($clientSecretB64))

# ════════════════════════════════════════════════════
# FONCTION LOG
# ════════════════════════════════════════════════════
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "CRITICAL" { Write-Host $logEntry -ForegroundColor Magenta }
        default { Write-Host $logEntry }
    }
    
    "$logEntry" | Out-File $logFile -Append -Force
}

Write-Log "=================================================" "CRITICAL"
Write-Log "ROLLBACK VERS FONDATION v10.3 EN COURS" "CRITICAL"
Write-Log "=================================================" "CRITICAL"

# Télécharger agent v10.3 depuis Azure
$agentUrl = "https://white-river-053fc6703.2.azurestaticapps.net/public/agent-v10.3.ps1"
$agentPath = "C:\SYAGA-ATLAS\agent.ps1"

Write-Log "Téléchargement agent v10.3 fondation..." "WARNING"

try {
    $agent = Invoke-WebRequest -Uri $agentUrl -UseBasicParsing
    $agent.Content | Out-File $agentPath -Encoding UTF8 -Force
    
    Write-Log "ROLLBACK RÉUSSI - Agent v10.3 restauré" "SUCCESS"
    
    # Redémarrer tâche agent
    Stop-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
    
    Write-Log "Tâche agent redémarrée avec v10.3" "SUCCESS"
    
    # Test immédiat
    Write-Log "Test de l'agent v10.3..." "INFO"
    & PowerShell.exe -ExecutionPolicy Bypass -File $agentPath
    
} catch {
    Write-Log "ERREUR ROLLBACK: $_" "ERROR"
    exit 1
}

Write-Log "=================================================" "SUCCESS"
Write-Log "ROLLBACK VERS v10.3 TERMINÉ AVEC SUCCÈS" "SUCCESS"
Write-Log "Le serveur est maintenant sur la fondation stable" "SUCCESS"
Write-Log "=================================================" "SUCCESS"