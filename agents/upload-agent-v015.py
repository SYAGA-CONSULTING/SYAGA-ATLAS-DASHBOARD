#!/usr/bin/env python3
"""
Upload agent v0.15 dans SharePoint pour déclencher auto-update
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

def upload_agent_v015():
    print("UPLOAD AGENT v0.15 vers SharePoint")
    print("=" * 40)
    
    config = load_config()
    token = get_token(config)
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    # Lire le fichier agent v0.15
    with open("/mnt/c/temp/AGENT-V0.15-IDENTIQUE.ps1", 'r', encoding='utf-8') as f:
        agent_content = f.read()
    
    print(f"Agent v0.15 lu: {len(agent_content)} caractères")
    
    # Encoder en base64 pour SharePoint
    content_b64 = base64.b64encode(agent_content.encode('utf-8')).decode('utf-8')
    
    # URL du fichier atlas-agent-current.ps1 dans SharePoint
    file_url = "https://graph.microsoft.com/v1.0/sites/syagacons.sharepoint.com/drive/root:/ATLAS/atlas-agent-current.ps1:/content"
    
    # Vérifier si le fichier existe déjà
    print("Vérification fichier existant...")
    try:
        check_response = requests.get(file_url.replace(':/content', ''), headers={'Authorization': f'Bearer {token}'})
        if check_response.status_code == 200:
            print("Fichier atlas-agent-current.ps1 existe déjà - mise à jour")
            file_exists = True
        else:
            print("Fichier n'existe pas - création")
            file_exists = False
    except:
        file_exists = False
    
    # Upload via PUT (écrase le fichier existant)
    print("Upload agent v0.15...")
    upload_headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'text/plain; charset=utf-8'
    }
    
    response = requests.put(file_url, headers=upload_headers, data=agent_content.encode('utf-8'))
    
    if response.status_code in [200, 201]:
        print("✅ Agent v0.15 uploadé avec succès dans SharePoint!")
        print("   Path: /ATLAS/atlas-agent-current.ps1")
        print("   L'agent v0.14 sur SYAGA-HOST01 devrait détecter cette version dans 1-2 minutes")
        return True
    else:
        print(f"❌ Erreur upload: {response.status_code}")
        print(response.text[:500])
        return False

if __name__ == "__main__":
    upload_agent_v015()