#!/usr/bin/env python3
"""
ATLAS - Déploiement RÉEL sur serveurs SharePoint
Phase par phase avec contrôle total
"""

import json
import base64
import requests
from datetime import datetime
import time
import os
from pathlib import Path

class RealServerDeployment:
    def __init__(self):
        # Charger config SP élevé
        with open(Path.home() / ".azure_elevated_sp.json") as f:
            self.sp_config = json.load(f)
        
        self.tenant_id = self.sp_config["TenantId"]
        self.client_id = self.sp_config["ClientId"]
        self.client_secret = self.sp_config["ClientSecret"]
        
        # SharePoint correct
        self.site_url = "https://syagacons.sharepoint.com/sites/SYAGA-ATLAS"
        self.token = None
        
    def get_token(self):
        """Obtenir token Microsoft Graph"""
        token_url = f"https://login.microsoftonline.com/{self.tenant_id}/oauth2/v2.0/token"
        
        body = {
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "scope": "https://graph.microsoft.com/.default",
            "grant_type": "client_credentials"
        }
        
        response = requests.post(token_url, data=body)
        if response.status_code == 200:
            self.token = response.json()["access_token"]
            return True
        else:
            print(f"❌ Erreur auth: {response.status_code}")
            return False
    
    def deploy_phase1_validation(self):
        """Déployer script validation v10.3 via UPDATE_CONFIG"""
        print("\n📋 PHASE 1: Validation v10.3 sur serveurs réels")
        print("=" * 60)
        
        # Lire le script Phase 1
        phase1_script = """
# ATLAS VALIDATION v10.3 - Déploiement réel
$Results = @{
    Hostname = $env:COMPUTERNAME
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Version = "v10.3"
    Tests = @{}
}

Write-Host "Validation ATLAS v10.3 sur $env:COMPUTERNAME" -ForegroundColor Cyan

# Test 1: Agent présent
if (Test-Path "C:\SYAGA-ATLAS\agent.ps1") {
    $Results.Tests["Agent"] = "PASS"
    Write-Host "✓ Agent présent" -ForegroundColor Green
} else {
    $Results.Tests["Agent"] = "FAIL"
    Write-Host "✗ Agent manquant" -ForegroundColor Red
}

# Test 2: Tâches planifiées
$agentTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Agent" -ErrorAction SilentlyContinue
$updaterTask = Get-ScheduledTask -TaskName "SYAGA-ATLAS-Updater" -ErrorAction SilentlyContinue

if ($agentTask -and $updaterTask) {
    $Results.Tests["Tasks"] = "PASS"
    Write-Host "✓ Tâches OK" -ForegroundColor Green
} else {
    $Results.Tests["Tasks"] = "FAIL"
    Write-Host "✗ Tâches manquantes" -ForegroundColor Red
}

# Test 3: Backup
$backupPath = "C:\SYAGA-BACKUP-v10.3"
if (-not (Test-Path $backupPath)) {
    Copy-Item -Path "C:\SYAGA-ATLAS" -Destination $backupPath -Recurse -Force
    $Results.Tests["Backup"] = "CREATED"
    Write-Host "✓ Backup créé" -ForegroundColor Green
} else {
    $Results.Tests["Backup"] = "EXISTS"
    Write-Host "✓ Backup existant" -ForegroundColor Green
}

# Test 4: Performance
$cpu = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$Results.Tests["CPU"] = $cpu

# Envoyer résultats à SharePoint
try {
    # Créer entrée dans SharePoint avec résultats
    $jsonResults = $Results | ConvertTo-Json -Compress
    
    # Pour UPDATE-ATLAS.ps1 compatibility
    $State = if ($Results.Tests.Values -contains "FAIL") { "NEEDS_ATTENTION" } else { "VALIDATED" }
    
    # Mettre à jour via méthode standard agent
    Write-Host "Résultats validation: $State" -ForegroundColor Yellow
    
    # Créer fichier local de résultats
    $Results | ConvertTo-Json | Out-File "C:\SYAGA-ATLAS\validation-results.json" -Encoding UTF8
    
} catch {
    Write-Host "Erreur envoi résultats: $_" -ForegroundColor Red
}

Write-Host "Validation terminée sur $env:COMPUTERNAME" -ForegroundColor Green
"""
        
        # Encoder en Base64
        script_b64 = base64.b64encode(phase1_script.encode('utf-8')).decode('ascii')
        
        # Créer UPDATE_CONFIG
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json;charset=utf-8"
        }
        
        # Payload pour UPDATE_CONFIG
        update_config = {
            "fields": {
                "Title": "UPDATE_CONFIG",
                "VeeamStatus": script_b64,  # Le champ que UPDATE-ATLAS.ps1 cherche
                "State": "PHASE1_VALIDATION",
                "DiskSpaceGB": "1001",  # Version spéciale pour phase 1
                "Modified": datetime.utcnow().isoformat() + "Z"
            }
        }
        
        # Vérifier si UPDATE_CONFIG existe
        check_url = f"{self.site_url}/_api/web/lists/getbytitle('ATLAS-Servers')/items?$filter=Title eq 'UPDATE_CONFIG'"
        
        try:
            check_response = requests.get(check_url, headers=headers)
            
            if check_response.status_code == 200:
                data = check_response.json()
                
                if data.get("value"):  # API v2 format
                    # Mettre à jour existant
                    item_id = data["value"][0]["id"]
                    update_url = f"{self.site_url}/_api/web/lists/getbytitle('ATLAS-Servers')/items('{item_id}')"
                    
                    headers["IF-MATCH"] = "*"
                    response = requests.patch(update_url, headers=headers, json=update_config)
                    
                    if response.status_code in [200, 204]:
                        print("✅ UPDATE_CONFIG mis à jour pour Phase 1")
                        return True
                else:
                    # Créer nouveau
                    create_url = f"{self.site_url}/_api/web/lists/getbytitle('ATLAS-Servers')/items"
                    response = requests.post(create_url, headers=headers, json=update_config)
                    
                    if response.status_code == 201:
                        print("✅ UPDATE_CONFIG créé pour Phase 1")
                        return True
                        
        except Exception as e:
            print(f"❌ Erreur déploiement: {e}")
            
        return False
    
    def wait_for_results(self, phase_name, timeout_minutes=5):
        """Attendre les résultats des agents"""
        print(f"\n⏳ Attente résultats {phase_name} (max {timeout_minutes} min)...")
        
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/json"
        }
        
        start_time = time.time()
        timeout = timeout_minutes * 60
        
        while time.time() - start_time < timeout:
            try:
                # Chercher les serveurs mis à jour
                url = f"{self.site_url}/_api/web/lists/getbytitle('ATLAS-Servers')/items?$filter=State eq 'VALIDATED'"
                response = requests.get(url, headers=headers)
                
                if response.status_code == 200:
                    data = response.json()
                    servers = data.get("value", [])
                    
                    if servers:
                        print(f"\n✅ {len(servers)} serveur(s) validé(s):")
                        for server in servers:
                            print(f"  - {server.get('Title', 'Unknown')}: {server.get('State', 'N/A')}")
                        return True
                        
            except Exception as e:
                print(f".", end="", flush=True)
            
            time.sleep(30)
        
        print("\n⏱️ Timeout - Pas de résultats")
        return False
    
    def cleanup_update_config(self):
        """Nettoyer UPDATE_CONFIG après déploiement"""
        print("\n🧹 Nettoyage UPDATE_CONFIG...")
        
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json;charset=utf-8"
        }
        
        update_config = {
            "fields": {
                "VeeamStatus": "",  # Vider le script
                "State": "COMPLETED",
                "Modified": datetime.utcnow().isoformat() + "Z"
            }
        }
        
        try:
            check_url = f"{self.site_url}/_api/web/lists/getbytitle('ATLAS-Servers')/items?$filter=Title eq 'UPDATE_CONFIG'"
            check_response = requests.get(check_url, headers=headers)
            
            if check_response.status_code == 200:
                data = check_response.json()
                if data.get("value"):
                    item_id = data["value"][0]["id"]
                    update_url = f"{self.site_url}/_api/web/lists/getbytitle('ATLAS-Servers')/items('{item_id}')"
                    
                    headers["IF-MATCH"] = "*"
                    requests.patch(update_url, headers=headers, json=update_config)
                    print("✅ UPDATE_CONFIG nettoyé")
                    
        except Exception as e:
            print(f"⚠️ Erreur nettoyage: {e}")
    
    def run_deployment(self):
        """Orchestration du déploiement phase par phase"""
        print("🚀 DÉPLOIEMENT RÉEL ATLAS - PHASES 1-3")
        print("=" * 60)
        
        # Authentification
        if not self.get_token():
            print("❌ Échec authentification")
            return
        
        print("✅ Authentification réussie")
        
        # Phase 1: Validation
        if self.deploy_phase1_validation():
            print("📡 Script envoyé aux agents via UPDATE_CONFIG")
            print("⏰ Les agents vont l'exécuter dans ~2 minutes")
            
            # Attendre résultats
            if self.wait_for_results("Phase 1"):
                print("\n✅ PHASE 1 COMPLÉTÉE - v10.3 validée")
                
                # Continuer avec Phase 2 si succès
                print("\n🔄 Prêt pour Phase 2: Tests rollback")
                # self.deploy_phase2_rollback()
                
            else:
                print("\n⚠️ Phase 1 incomplète - Vérifier manuellement")
        
        # Nettoyer
        self.cleanup_update_config()
        
        print("\n✅ Déploiement terminé")

if __name__ == "__main__":
    deployer = RealServerDeployment()
    deployer.run_deployment()