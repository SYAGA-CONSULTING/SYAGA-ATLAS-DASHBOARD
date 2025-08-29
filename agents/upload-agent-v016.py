#!/usr/bin/env python3
"""
Upload agent v0.16 dans SharePoint pour déclencher auto-update
"""

import json
import requests
import base64

def load_config():
    config = {}
    with open("/home/sq/.azure_config", 'r') as f:
        for line in f:
            if '=' in line and not line.startswith('#'):
                key, value = line.strip().split('=', 1)
                config[key.lower()] = value
    return config

def get_token(config):
    token_url = f"https://login.microsoftonline.com/{config['tenant_id']}/oauth2/v2.0/token"
    data = {
        'client_id': config['client_id'],
        'client_secret': config['client_secret'],
        'scope': 'https://graph.microsoft.com/.default',
        'grant_type': 'client_credentials'
    }
    response = requests.post(token_url, data=data)
    return response.json()['access_token']

def upload_agent_v016():
    print("UPLOAD AGENT v0.16 - MÉTRIQUES BASE RÉELLES")
    print("=" * 50)
    
    config = load_config()
    token = get_token(config)
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'text/plain; charset=utf-8'
    }
    
    # Lire le fichier agent v0.16
    with open("/mnt/c/temp/AGENT-V0.16-METRIQUES-BASE.ps1", 'r', encoding='utf-8') as f:
        agent_content = f.read()
    
    print(f"Agent v0.16 lu: {len(agent_content)} caractères")
    print("Nouveautés: CPU/RAM/Disk réels + logs ATLAS_LOGS")
    
    # URL du fichier atlas-agent-current.ps1 dans SharePoint
    file_url = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com/drive/root:/ATLAS/atlas-agent-current.ps1:/content"
    
    # Upload via PUT (écrase le fichier existant)
    print("Upload agent v0.16...")
    response = requests.put(file_url, headers=headers, data=agent_content.encode('utf-8'))
    
    if response.status_code in [200, 201]:
        print("✅ Agent v0.16 uploadé avec succès dans SharePoint!")
        print("   Path: /ATLAS/atlas-agent-current.ps1")
        print("   SYAGA-HOST01 v0.15 → v0.16 dans 1-2 minutes")
        print("")
        print("🔍 SURVEILLANCE OBLIGATOIRE:")
        print("   - Attendre 5-10 minutes")
        print("   - Vérifier aucune erreur dans ATLAS_LOGS")
        print("   - Confirmer métriques CPU/RAM/Disk réelles")
        print("   - Si stable → Continuer Catégorie 2 Hyper-V")
        return True
    else:
        print(f"❌ Erreur upload: {response.status_code}")
        print(response.text[:500])
        return False

if __name__ == "__main__":
    upload_agent_v016()