#!/usr/bin/env python3
"""
Upload agent v0.19 - EXACTEMENT comme v0.15 à v0.18
"""

import json
import requests

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

def upload_agent_v019():
    print("🚀 UPLOAD AGENT v0.19 - VERSION FINALE")
    print("=" * 50)
    
    config = load_config()
    token = get_token(config)
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'text/plain; charset=utf-8'
    }
    
    # Lire l'agent v0.19
    with open("/mnt/c/temp/AGENT-V0.19-UNIFIED.ps1", 'r', encoding='utf-8') as f:
        agent_content = f.read()
    
    # Upload vers SharePoint Documents (même endroit que v0.15-v0.18)
    docs_url = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com,4cce268e-9cb7-4829-8c1c-3c85faa1810d,8cb3611e-c4aa-4105-b55d-2247e4fac8c8/drive/root:/Documents%20partages/ATLAS/atlas-agent-current.ps1:/content"
    
    print("📤 Upload vers SharePoint Documents/ATLAS...")
    response = requests.put(docs_url, headers=headers, data=agent_content.encode('utf-8'))
    
    if response.status_code in [200, 201]:
        print("✅ Agent v0.19 uploadé avec succès!")
        print("")
        print("🎯 AUTO-UPDATE v0.19 EN COURS")
        print("=" * 40)
        print("Les agents v0.18 vont:")
        print("1. Détecter nouvelle version")
        print("2. Télécharger v0.19")  
        print("3. S'installer automatiquement")
        print("4. Redémarrer en v0.19")
        print("")
        print("⏱️  Attendez 2-4 minutes")
        print("📊 Dashboard: https://syaga-atlas.azurestaticapps.net")
        return True
    else:
        print(f"❌ Erreur upload v0.19: {response.status_code}")
        print(response.text[:500])
        return False

if __name__ == "__main__":
    upload_agent_v019()