#!/usr/bin/env python3
"""
Créer commande ROLLBACK_TO_v10.3 dans SharePoint
"""
import requests
import base64

# Config SharePoint
tenant_id = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
client_id = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
client_secret_b64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
client_secret = base64.b64decode(client_secret_b64).decode('utf-8')

print("🔄 CRÉATION COMMANDE ROLLBACK v10.3")
print("="*60)

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
    "Content-Type": "application/json;odata=verbose"
}

commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

# Créer commande rollback
command_data = {
    "__metadata": {"type": "SP.Data.ATLASCommandsListItem"},
    "Title": "ROLLBACK_TO_v10.3_FOUNDATION",
    "CommandType": "ROLLBACK",
    "TargetHostname": "ALL", 
    "TargetVersion": "10.3",
    "Status": "PENDING",
    "CreatedBy": "Claude_ROLLBACK_SYSTEM"
}

create_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items"

print("📤 Création commande ROLLBACK...")
response = requests.post(create_url, headers=headers, json=command_data)

if response.status_code == 201:
    item = response.json()["d"]
    print("✅ Commande ROLLBACK créée !")
    print(f"   ID: {item.get('Id')}")
    print(f"   Title: ROLLBACK_TO_v10.3_FOUNDATION")
    print(f"   CommandType: ROLLBACK")
    print(f"   TargetVersion: 10.3")
    
    print("\n🎯 L'updater va détecter cette commande et:")
    print("1. Télécharger rollback-v10.3.ps1")
    print("2. Exécuter le rollback vers fondation")
    print("3. Restaurer agent-v10.3.ps1 stable")
    
else:
    print(f"❌ Erreur: {response.status_code}")
    print(response.text)

print("="*60)