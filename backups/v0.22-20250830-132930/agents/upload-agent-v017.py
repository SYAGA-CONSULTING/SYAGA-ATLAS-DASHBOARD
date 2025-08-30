#!/usr/bin/env python3
"""
Upload agent v0.17 avec Hyper-V détaillé dans SharePoint
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

def upload_agent_v017():
    print("🚀 UPLOAD AGENT v0.17 - HYPER-V DÉTAILLÉ")
    print("=" * 55)
    
    config = load_config()
    token = get_token(config)
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'text/plain; charset=utf-8'
    }
    
    # Lire l'agent v0.17
    with open("/mnt/c/temp/AGENT-V0.17-HYPERV.ps1", 'r', encoding='utf-8') as f:
        agent_content = f.read()
    
    print(f"Agent v0.17 lu: {len(agent_content)} caractères")
    print("🔥 NOUVEAUTÉS v0.17:")
    print("   • État détaillé par VM (Running/Stopped/Paused)")
    print("   • CPU/RAM/Uptime par VM")
    print("   • Checkpoints count par VM")
    print("   • Réplication Hyper-V (état + santé)")
    print("   • Logs détaillés par VM dans ATLAS_LOGS")
    print("")
    
    # Upload vers SharePoint
    file_url = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com/drive/root:/ATLAS/atlas-agent-current.ps1:/content"
    
    print("⬆️  Upload agent v0.17...")
    response = requests.put(file_url, headers=headers, data=agent_content.encode('utf-8'))
    
    if response.status_code in [200, 201]:
        print("✅ Agent v0.17 HYPER-V uploadé avec succès!")
        print("   Path: /ATLAS/atlas-agent-current.ps1")
        print("   Auto-update: SYAGA-HOST01 v0.16 → v0.17 dans 1-2 minutes")
        print("")
        print("📊 SURVEILLANCE v0.17:")
        print("   🔍 Hyper-V VMs détectées et analysées")
        print("   🔍 Réplication status par VM")
        print("   🔍 Logs détaillés dans ATLAS_LOGS")
        print("   ⚠️  Surveiller 5-10 minutes pour erreurs")
        print("")
        print("✅ Si stable → Catégorie 3: Veeam Backup")
        return True
    else:
        print(f"❌ Erreur upload v0.17: {response.status_code}")
        print(response.text[:500])
        return False

if __name__ == "__main__":
    upload_agent_v017()