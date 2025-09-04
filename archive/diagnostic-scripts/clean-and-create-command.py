#!/usr/bin/env python3
"""
Nettoyer les anciennes commandes et créer une nouvelle
"""
import json
import requests
import base64
from datetime import datetime

# Config SharePoint
tenant_id = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
client_id = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
client_secret_b64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
client_secret = base64.b64decode(client_secret_b64).decode('utf-8')

# Token
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
    "Content-Type": "application/json;odata=verbose;charset=utf-8"
}

print("="*60)
print("🧹 NETTOYAGE ET CRÉATION COMMANDE v8.1")
print("="*60)

# 1. Marquer les anciennes commandes comme CANCELLED
commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"
get_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items?$filter=Status eq 'PENDING'&$select=Id"

response = requests.get(get_url, headers=headers)
if response.status_code == 200:
    items = response.json()["d"]["results"]
    
    print(f"\n📋 Nettoyage de {len(items)} anciennes commandes...")
    
    for item in items:
        item_id = item["Id"]
        update_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items({item_id})"
        
        update_data = {
            "__metadata": {"type": "SP.Data.ATLASCommandsListItem"},
            "Status": "CANCELLED"
        }
        
        update_headers = headers.copy()
        update_headers["X-HTTP-Method"] = "MERGE"
        update_headers["IF-MATCH"] = "*"
        
        response = requests.post(update_url, headers=update_headers, json=update_data)
        if response.status_code in [200, 204]:
            print(f"   ✅ Commande ID {item_id} annulée")
        else:
            print(f"   ❌ Erreur annulation ID {item_id}")

# 2. Créer une nouvelle commande v8.1
print(f"\n📝 Création nouvelle commande UPDATE v8.1...")

create_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items"

command_data = {
    "__metadata": {"type": "SP.Data.ATLASCommandsListItem"},
    "Title": f"UPDATE_v8.1_{datetime.now().strftime('%H%M%S')}",
    "CommandType": "UPDATE_ALL",
    "TargetHostname": "ALL",
    "Status": "PENDING",
    "TargetVersion": "8.1",
    "CreatedBy": "Claude"
}

response = requests.post(create_url, headers=headers, json=command_data)

if response.status_code in [200, 201]:
    result = response.json()["d"]
    print("\n✅ NOUVELLE COMMANDE CRÉÉE")
    print(f"   • ID: {result.get('Id')}")
    print(f"   • Type: UPDATE_ALL")
    print(f"   • Target: ALL")
    print(f"   • Version: 8.1")
    print(f"   • Status: PENDING")
    print("\n🎯 Les agents vont détecter cette commande dans 1 minute")
    print("   et se mettre à jour vers v8.1")
else:
    print(f"❌ Erreur création: {response.status_code}")

print("="*60)