# ATLAS Agent v10.5 - ÉCHEC RÉSEAU POUR TEST ROLLBACK
$script:Version = "10.5"
$hostname = $env:COMPUTERNAME
$logFile = "C:\SYAGA-ATLAS\atlas_log.txt"

function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Host $logEntry -ForegroundColor Red
    "$logEntry" | Out-File $logFile -Append -Force
}

Write-Log "Agent v10.5 - NETWORK FAILURE VERSION" "ERROR"

# ERREUR VOLONTAIRE : Tentative connexion serveur inexistant
Write-Log "Tentative connexion serveur inexistant..." "ERROR"

try {
    # URL volontairement fausse
    $response = Invoke-RestMethod -Uri "https://serveur-inexistant-12345.com/api/data" -TimeoutSec 30
} catch {
    Write-Log "ERREUR RÉSEAU: $_" "ERROR"
}

# ERREUR VOLONTAIRE : SharePoint avec mauvais credentials
Write-Log "Tentative SharePoint avec credentials corrompus..." "ERROR"

$badToken = "FAKE_TOKEN_FOR_TESTING"
$headers = @{
    Authorization = "Bearer $badToken"
    Accept = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri "https://syagacons.sharepoint.com/_api/web/lists" -Headers $headers
} catch {
    Write-Log "ERREUR SHAREPOINT: $_" "ERROR"
}

Write-Log "Agent v10.5 échoue volontairement pour test rollback" "ERROR"
Write-Log "Cette version doit déclencher un rollback automatique vers v10.3" "WARNING"

# Simuler crash
throw "ERREUR CRITIQUE SIMULÉE - ROLLBACK REQUIS"