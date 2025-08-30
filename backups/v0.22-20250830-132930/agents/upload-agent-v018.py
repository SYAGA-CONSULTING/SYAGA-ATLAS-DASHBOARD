#!/usr/bin/env python3
"""
Upload agent v0.18 avec Veeam Backup détaillé
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

def upload_agent_v018():
    print("🎯 UPLOAD AGENT v0.18 - VEEAM BACKUP DÉTAILLÉ")
    print("=" * 55)
    
    config = load_config()
    token = get_token(config)
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'text/plain; charset=utf-8'
    }
    
    # Lire l'agent v0.18
    with open("/mnt/c/temp/AGENT-V0.18-VEEAM.ps1", 'r', encoding='utf-8') as f:
        agent_content = f.read()
    
    print(f"Agent v0.18 lu: {len(agent_content)} caractères")
    print("🔥 NOUVEAUTÉS v0.18 - VEEAM:")
    print("   • Détection Veeam (3 méthodes)")
    print("   • Jobs backup (Success/Warning/Failed)")
    print("   • Dernière date backup")
    print("   • Taille totale backups GB")
    print("   • État détaillé par job")
    print("   • Logs individuels par job Veeam")
    print("")
    
    # Upload vers SharePoint
    file_url = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com/drive/root:/ATLAS/atlas-agent-current.ps1:/content"
    
    print("⬆️  Upload agent v0.18 Veeam...")
    response = requests.put(file_url, headers=headers, data=agent_content.encode('utf-8'))
    
    if response.status_code in [200, 201]:
        print("✅ Agent v0.18 VEEAM uploadé avec succès!")
        print("   Auto-update: SYAGA-HOST01 v0.17.1 → v0.18 dans 1-2 minutes")
        print("")
        print("📊 SURVEILLANCE v0.18:")
        print("   🔍 Veeam détecté ou pas")
        print("   📦 Jobs backup comptabilisés")
        print("   💾 Taille backups calculée")
        print("   📜 Logs détaillés par job Veeam")
        print("   ⚠️  Surveiller 5-10 minutes pour erreurs")
        print("")
        print("✅ Si stable → Catégorie 4: Windows Update")
        return True
    else:
        print(f"❌ Erreur upload v0.18: {response.status_code}")
        print(response.text[:500])
        return False

if __name__ == "__main__":
    upload_agent_v018()