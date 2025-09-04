#!/usr/bin/env python3
"""
ATLAS - Déploiement Autonome Test Validation v10.3
Utilise l'auto-update pour tester et rollback si nécessaire
"""

import json
import base64
import requests
from datetime import datetime, timedelta
import time
import os
from pathlib import Path

# Configuration - Utiliser le SP élevé qui a les droits
CLIENT_ID = "1aaba66f-e472-4ca0-83a6-df32340f6d58"  # SP élevé avec droits SharePoint
TENANT_ID = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
SITE_URL = "https://syagacons.sharepoint.com/sites/SYAGA-ATLAS"  # syagacons = domaine correct

def get_token():
    """Obtenir token avec Service Principal élevé"""
    # Utiliser le SP élevé qui a les droits SharePoint
    config_path = Path.home() / ".azure_elevated_sp.json"
    with open(config_path) as f:
        config = json.load(f)
    
    token_url = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"
    
    body = {
        "client_id": CLIENT_ID,
        "client_secret": config["ClientSecret"],
        "scope": "https://graph.microsoft.com/.default",
        "grant_type": "client_credentials"
    }
    
    response = requests.post(token_url, data=body)
    response.raise_for_status()
    return response.json()["access_token"]

def create_validation_command():
    """Créer commande TEST_V10_VALIDATION dans SharePoint"""
    print("🎯 Création commande TEST_V10_VALIDATION...")
    
    token = get_token()
    
    # Lire le script de validation
    with open("/home/sq/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/public/agent-v10.3-validation.ps1", "r", encoding="utf-8") as f:
        script_content = f.read()
    
    # Encoder en Base64
    script_b64 = base64.b64encode(script_content.encode('utf-8')).decode('ascii')
    
    # Créer la commande
    command_data = {
        "fields": {
            "Title": "TEST_V10_VALIDATION",
            "Command": "EXECUTE_VALIDATION",
            "Parameters": json.dumps({
                "action": "test_validation",
                "version": "v10.3",
                "rollback_on_fail": True,
                "script": script_b64
            }),
            "Status": "PENDING",
            "CreatedTime": datetime.utcnow().isoformat() + "Z",
            "Target": "ALL_SERVERS",
            "Priority": "HIGH"
        }
    }
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json;charset=utf-8"
    }
    
    url = f"{SITE_URL}/_api/web/lists/getbytitle('ATLAS-Commands')/items"
    
    response = requests.post(url, headers=headers, json=command_data)
    
    if response.status_code in [200, 201]:
        print("✅ Commande créée avec succès")
        return response.json()["d"]["Id"]
    else:
        print(f"❌ Erreur création commande: {response.status_code}")
        print(response.text)
        return None

def deploy_validation_via_update_config():
    """Déployer via UPDATE_CONFIG pour auto-update"""
    print("📦 Déploiement via UPDATE_CONFIG...")
    
    token = get_token()
    
    # Lire le script de validation
    with open("/home/sq/SYAGA-CONSULTING/SYAGA-ATLAS-DASHBOARD/public/agent-v10.3-validation.ps1", "r", encoding="utf-8") as f:
        script_content = f.read()
    
    # Créer script wrapper qui teste et rollback si nécessaire
    wrapper_script = r"""
# ATLAS Auto-Validation Wrapper
# Teste v10.3 et rollback automatique si échec

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   ATLAS AUTO-VALIDATION v10.3 AVEC ROLLBACK" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Sauvegarder le script de validation
$validationScript = @'
{VALIDATION_SCRIPT}
'@

$validationScript | Out-File "C:\SYAGA-ATLAS\agent-validation.ps1" -Encoding UTF8

# Exécuter validation
Write-Host "Lancement validation..." -ForegroundColor Green
& "C:\SYAGA-ATLAS\agent-validation.ps1" -TestValidation

# Le script gère le rollback automatiquement si échec
Write-Host "Validation terminée" -ForegroundColor Green
""".replace("{VALIDATION_SCRIPT}", script_content)
    
    # Encoder en Base64
    script_b64 = base64.b64encode(wrapper_script.encode('utf-8')).decode('ascii')
    
    # Créer/Mettre à jour UPDATE_CONFIG
    update_config = {
        "fields": {
            "Title": "UPDATE_CONFIG",
            "VeeamStatus": script_b64,  # Le champ attendu par UPDATE-ATLAS.ps1
            "State": "ACTIVE",
            "DiskSpaceGB": "999",  # Version spéciale validation
            "Modified": datetime.utcnow().isoformat() + "Z"
        }
    }
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json;charset=utf-8"
    }
    
    # Vérifier si UPDATE_CONFIG existe
    check_url = f"{SITE_URL}/_api/web/lists/getbytitle('ATLAS-Servers')/items?$filter=Title eq 'UPDATE_CONFIG'"
    check_response = requests.get(check_url, headers=headers)
    
    if check_response.json()["d"]["results"]:
        # Mettre à jour existant
        item_id = check_response.json()["d"]["results"][0]["Id"]
        url = f"{SITE_URL}/_api/web/lists/getbytitle('ATLAS-Servers')/items({item_id})"
        headers["IF-MATCH"] = "*"
        headers["X-HTTP-Method"] = "MERGE"
        response = requests.post(url, headers=headers, json=update_config)
        print(f"✅ UPDATE_CONFIG mis à jour (ID: {item_id})")
    else:
        # Créer nouveau
        url = f"{SITE_URL}/_api/web/lists/getbytitle('ATLAS-Servers')/items"
        response = requests.post(url, headers=headers, json=update_config)
        print("✅ UPDATE_CONFIG créé")
    
    return True

def wait_for_results(timeout_minutes=5):
    """Attendre et récupérer résultats de validation"""
    print(f"⏳ Attente des résultats (max {timeout_minutes} min)...")
    
    token = get_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json"
    }
    
    start_time = datetime.now()
    timeout = timedelta(minutes=timeout_minutes)
    
    while datetime.now() - start_time < timeout:
        # Vérifier les résultats de validation
        url = f"{SITE_URL}/_api/web/lists/getbytitle('ATLAS-ValidationResults')/items?$top=10&$orderby=Created desc"
        
        try:
            response = requests.get(url, headers=headers)
            if response.status_code == 200:
                results = response.json()["d"]["results"]
                
                if results:
                    latest = results[0]
                    print(f"\n📊 Résultat reçu de {latest['Hostname']}:")
                    print(f"   Status: {latest['Status']}")
                    print(f"   Peut continuer: {latest.get('CanContinue', 'Unknown')}")
                    
                    # Analyser le status
                    if latest['Status'] == "READY_FOR_EVOLUTION":
                        print("✅ VALIDATION RÉUSSIE - Prêt pour évolution!")
                        return "SUCCESS"
                    elif latest['Status'] == "ROLLBACK_REQUIRED":
                        print("🔴 ROLLBACK AUTOMATIQUE DÉCLENCHÉ")
                        return "ROLLBACK"
                    elif latest['Status'] == "PARTIAL_SUCCESS":
                        print("⚠️ Validation partielle - Corrections mineures requises")
                        return "PARTIAL"
                        
        except Exception as e:
            print(f"Erreur récupération résultats: {e}")
        
        time.sleep(30)  # Attendre 30 secondes avant de réessayer
        print(".", end="", flush=True)
    
    print("\n⏱️ Timeout - Pas de résultats reçus")
    return "TIMEOUT"

def cleanup_update_config():
    """Nettoyer UPDATE_CONFIG après test"""
    print("🧹 Nettoyage UPDATE_CONFIG...")
    
    token = get_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json;charset=utf-8"
    }
    
    # Remettre UPDATE_CONFIG normal
    update_config = {
        "fields": {
            "Title": "UPDATE_CONFIG",
            "VeeamStatus": "",  # Vider le script
            "State": "COMPLETED",
            "Modified": datetime.utcnow().isoformat() + "Z"
        }
    }
    
    check_url = f"{SITE_URL}/_api/web/lists/getbytitle('ATLAS-Servers')/items?$filter=Title eq 'UPDATE_CONFIG'"
    check_response = requests.get(check_url, headers=headers)
    
    if check_response.json()["d"]["results"]:
        item_id = check_response.json()["d"]["results"][0]["Id"]
        url = f"{SITE_URL}/_api/web/lists/getbytitle('ATLAS-Servers')/items({item_id})"
        headers["IF-MATCH"] = "*"
        headers["X-HTTP-Method"] = "MERGE"
        requests.post(url, headers=headers, json=update_config)
        print("✅ UPDATE_CONFIG nettoyé")

def main():
    """Orchestration principale du test autonome"""
    print("🚀 ATLAS - TEST VALIDATION AUTONOME v10.3")
    print("=" * 60)
    
    try:
        # 1. Déployer script de validation
        if deploy_validation_via_update_config():
            print("✅ Script de validation déployé via auto-update")
            
            # 2. Attendre que les agents récupèrent et exécutent
            print("\n⏳ Les agents vont récupérer le script dans ~2 minutes...")
            time.sleep(120)  # Attendre 2 minutes
            
            # 3. Attendre les résultats
            result = wait_for_results()
            
            # 4. Analyser et décider
            print("\n" + "=" * 60)
            if result == "SUCCESS":
                print("🎉 PHASE 1 VALIDÉE - v10.3 est stable!")
                print("Prochaine étape: Tests rollback dans 2h")
            elif result == "ROLLBACK":
                print("⚠️ Rollback automatique effectué")
                print("v10.3 restaurée - Analyser les logs")
            elif result == "PARTIAL":
                print("📝 Corrections mineures requises")
                print("Vérifier les détails dans SharePoint")
            else:
                print("❌ Test incomplet - Vérification manuelle requise")
            
            # 5. Nettoyer
            cleanup_update_config()
            
        else:
            print("❌ Échec déploiement")
            
    except Exception as e:
        print(f"❌ Erreur: {e}")
        cleanup_update_config()
        
    print("\n✅ Test autonome terminé")

if __name__ == "__main__":
    main()