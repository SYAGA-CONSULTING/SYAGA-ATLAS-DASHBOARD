#!/usr/bin/env python3
"""
Créer une commande UPDATE_ALL vers v9.1
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

headers = {"Authorization": f"Bearer {token}", "Accept": "application/json;odata=verbose"}

print("="*60)
print("🚀 CRÉATION COMMANDE UPDATE vers v9.1 (FINALE)")
print("="*60)

# Créer la commande dans ATLAS-Commands
commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"
create_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items"

command_data = {
    "__metadata": {"type": "SP.Data.ATLASCommandsListItem"},
    "Title": f"UPDATE_v9.1_FINAL_{datetime.now().strftime('%H%M%S')}",
    "CommandType": "UPDATE_ALL",
    "TargetHostname": "ALL",
    "Status": "PENDING",
    "TargetVersion": "9.1",
    "CreatedBy": "Claude"
}

create_headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/json;odata=verbose",
    "Content-Type": "application/json;odata=verbose;charset=utf-8"
}

try:
    response = requests.post(create_url, headers=create_headers, json=command_data)
    
    if response.status_code in [200, 201]:
        result = response.json()["d"]
        print("✅ COMMANDE UPDATE CRÉÉE AVEC SUCCÈS")
        print(f"   • ID: {result.get('Id')}")
        print(f"   • Type: UPDATE_ALL")
        print(f"   • Target: ALL")
        print(f"   • Version: 9.1")
        print(f"   • Status: PENDING")
        print("\n🎯 Les agents v8.1 actuels vont :")
        print("   1. Détecter cette commande")
        print("   2. Se mettre à jour vers v9.1")
        print("   3. v9.1 va enfin pouvoir lire les commandes !")
    else:
        print(f"❌ Erreur: {response.status_code}")
        print(response.text)
except Exception as e:
    print(f"❌ Exception: {e}")

print("="*60)