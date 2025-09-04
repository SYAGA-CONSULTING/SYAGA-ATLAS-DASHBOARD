#!/usr/bin/env python3
"""
Créer commande UPDATE dans la nouvelle liste ATLAS-Commands
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

# Obtenir token
token_url = f"https://accounts.accesscontrol.windows.net/{tenant_id}/tokens/OAuth/2"
token_body = {
    "grant_type": "client_credentials",
    "client_id": f"{client_id}@{tenant_id}",
    "client_secret": client_secret,
    "resource": f"00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@{tenant_id}"
}

print("🔐 Authentification...")
response = requests.post(token_url, data=token_body)
if response.status_code != 200:
    print(f"❌ Erreur: {response.text}")
    exit(1)

token = response.json()["access_token"]
print("✅ Token obtenu")

headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/json;odata=verbose",
    "Content-Type": "application/json;odata=verbose"
}

# Liste ATLAS-Commands
commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

print("\n" + "=" * 70)
print("📤 CRÉATION COMMANDE UPDATE_ALL VERS v7.0")
print("=" * 70)

# Créer commande UPDATE
command_data = {
    "__metadata": {"type": "SP.Data.ATLASCommandsListItem"},
    "Title": "UPDATE_ALL_v71",
    "CommandType": "UPDATE", 
    "TargetVersion": "7.1",
    "TargetHostname": "ALL",
    "Status": "PENDING",
    "CreatedBy": "Claude"
}

create_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items"
print("\n📝 Création commande...")
response = requests.post(create_url, headers=headers, json=command_data)

if response.status_code in [200, 201]:
    result = response.json()
    print("✅ COMMANDE CRÉÉE AVEC SUCCÈS!")
    print(f"  • ID: {result['d']['Id']}")
    print(f"  • Type: UPDATE")
    print(f"  • Version cible: 7.0")
    print(f"  • Target: ALL")
    print(f"  • Status: PENDING")
    print(f"  • Heure: {datetime.now().strftime('%H:%M:%S')}")
    
    print("\n⚡ Les agents v7.0 vont détecter cette commande dans la minute")
    print("📊 La nouvelle architecture sépare clairement:")
    print("  • Liste ATLAS-Servers: métriques et heartbeat")
    print("  • Liste ATLAS-Commands: commandes UPDATE_ALL, REBOOT, etc.")
else:
    print(f"❌ Erreur: {response.status_code}")
    print(response.text)

# Vérifier les commandes existantes
print("\n" + "=" * 70)
print("📋 COMMANDES EXISTANTES DANS ATLAS-Commands")
print("=" * 70)

search_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items?$select=Id,Title,CommandType,TargetVersion,TargetHostname,Status,CreatedBy,ExecutedBy,Created&$orderby=Created desc&$top=10"
headers_get = {"Authorization": f"Bearer {token}", "Accept": "application/json;odata=verbose"}
response = requests.get(search_url, headers=headers_get)

if response.status_code == 200:
    items = response.json()["d"]["results"]
    print(f"\n{len(items)} commande(s) trouvée(s):")
    for item in items:
        status_icon = "⏳" if item.get("Status") == "PENDING" else "✅"
        print(f"\n{status_icon} ID {item['Id']}: {item.get('Title', 'N/A')}")
        print(f"  • Type: {item.get('CommandType', 'N/A')}")
        print(f"  • Version: {item.get('TargetVersion', 'N/A')}")
        print(f"  • Target: {item.get('TargetHostname', 'N/A')}")
        print(f"  • Status: {item.get('Status', 'N/A')}")
        if item.get('ExecutedBy'):
            print(f"  • Exécuté par: {item.get('ExecutedBy')}")
else:
    print(f"Erreur lecture: {response.status_code}")