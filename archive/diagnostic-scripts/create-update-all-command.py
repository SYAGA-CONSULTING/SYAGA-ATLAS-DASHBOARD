#!/usr/bin/env python3
"""
Créer commande UPDATE_ALL dans la liste SharePoint ATLAS-Servers
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

print("🔐 Obtention du token OAuth...")
response = requests.post(token_url, data=token_body)
if response.status_code != 200:
    print(f"❌ Erreur obtention token: {response.text}")
    exit(1)

token = response.json()["access_token"]
print("✅ Token obtenu")

# Headers pour SharePoint
headers = {
    "Authorization": f"Bearer {token}",
    "Accept": "application/json;odata=verbose",
    "Content-Type": "application/json;odata=verbose"
}

# Liste ATLAS-Servers (même liste)
list_id = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"

# Créer commande UPDATE_ALL comme entry dans la même liste
command_data = {
    "__metadata": {"type": "SP.Data.ATLASServersListItem"},  # Même type que les serveurs
    "Title": "UPDATE_ALL",
    "AgentVersion": "6.2",
    "VeeamStatus": f"FORCER UPDATE vers v6.2 - {datetime.now().strftime('%Y-%m-%d %H:%M')}",
    "State": "UPDATE_COMMAND"
}

create_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{list_id}')/items"

print("\n📤 Création commande UPDATE_ALL vers v6.2...")
response = requests.post(create_url, headers=headers, json=command_data)

if response.status_code in [200, 201]:
    print("✅ Commande UPDATE_ALL créée avec succès")
    result = response.json()
    print(f"🆔 ID commande: {result['d']['Id']}")
    print(f"📝 Titre: {result['d']['Title']}")
    print(f"🔄 Version cible: v{result['d']['AgentVersion']}")
    print("\n⚡ Les agents vont détecter UPDATE_ALL dans la minute et se mettre à jour")
else:
    print(f"❌ Erreur création commande: {response.status_code}")
    print(response.text)

print("\n🔍 Vérification des serveurs actifs...")
# Chercher serveurs avec Hostname non-null pour voir les vrais serveurs
search_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{list_id}')/items?$filter=Hostname ne null&$select=Title,Hostname,AgentVersion,State,VeeamStatus&$orderby=Modified desc&$top=10"
response = requests.get(search_url, headers=headers)

if response.status_code == 200:
    items = response.json()["d"]["results"]
    print(f"📊 {len(items)} serveurs actifs:")
    for item in items:
        hostname = item.get("Hostname", "?")
        version = item.get("AgentVersion", "?")
        state = item.get("State", "?")
        status = item.get("VeeamStatus", "?")
        print(f"  • {hostname}: v{version} - {state} - {status}")