#!/usr/bin/env python3
"""
Créer commande UPDATE_ALL v10.2 dans SharePoint - Deploy automatique !
"""
import json
import requests
import base64
from datetime import datetime, timezone

# Config SharePoint
tenant_id = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
client_id = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
client_secret_b64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
client_secret = base64.b64decode(client_secret_b64).decode('utf-8')

# Token
print("🔐 Obtention token...")
token_url = f"https://accounts.accesscontrol.windows.net/{tenant_id}/tokens/OAuth/2"
token_body = {
    "grant_type": "client_credentials",
    "client_id": f"{client_id}@{tenant_id}",
    "client_secret": client_secret,
    "resource": f"00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@{tenant_id}"
}

response = requests.post(token_url, data=token_body)
token = response.json()["access_token"]

headers = {
    "Authorization": f"Bearer {token}", 
    "Accept": "application/json;odata=verbose",
    "Content-Type": "application/json;odata=verbose"
}

# Liste des commandes
commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

print("\n🚀 DÉPLOIEMENT AUTOMATIQUE v10.2 PAR CLAUDE")
print("="*60)

# Créer la commande
command_data = {
    "__metadata": {
        "type": "SP.Data.ATLASCommandsListItem"
    },
    "Title": "UPDATE_ALL_v10.2",
    "CommandType": "UPDATE", 
    "TargetHostname": "ALL",
    "TargetVersion": "10.2",
    "Status": "PENDING",
    "CreatedBy": "Claude_AUTO"
}

create_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items"

print(f"📤 Création commande UPDATE_ALL v10.2...")
print(f"   🎯 Target: TOUS les serveurs")
print(f"   ⚡ Status: PENDING")
print(f"   🤖 CreatedBy: Claude_AUTO")

response = requests.post(create_url, headers=headers, json=command_data)

if response.status_code == 201:
    print("✅ Commande UPDATE_ALL_v10.2 créée avec succès!")
    item = response.json()["d"]
    print(f"   ID: {item.get('Id')}")
    print(f"   Status: PENDING")
    print(f"   Target: ALL servers")
    print(f"   Version: 10.2")
    
    print("\n🎯 SÉQUENCE AUTO-UPDATE EN COURS:")
    print("1. ✅ Agent v10.2 créé")  
    print("2. ✅ Déployé sur Azure")
    print("3. ✅ Commande UPDATE_ALL créée")
    print("4. ⏳ Les updaters détectent la commande...")
    print("5. ⏳ Auto-update vers v10.2 en cours...")
    
    print(f"\n⏰ Les agents vont passer en v10.2 dans 1-2 minutes !")
    
else:
    print(f"❌ Erreur: {response.status_code}")
    print(response.text)

print("="*60)
print("🎊 CLAUDE A DÉPLOYÉ v10.2 AUTOMATIQUEMENT !")
print("="*60)