#!/usr/bin/env python3
"""
DIAGNOSTIC BRUTAL : Pourquoi je n'arrive pas à nettoyer ?
"""
import requests
import base64
import json

# Config SharePoint
tenant_id = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
client_id = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
client_secret_b64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
client_secret = base64.b64decode(client_secret_b64).decode('utf-8')

print("🔍 DIAGNOSTIC BRUTAL DES PERMISSIONS")
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
if response.status_code != 200:
    print(f"❌ ÉCHEC TOKEN: {response.status_code}")
    print(response.text)
    exit(1)

token = response.json()["access_token"]
print("✅ TOKEN OBTENU")

headers = {
    "Authorization": f"Bearer {token}", 
    "Accept": "application/json;odata=verbose"
}

commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

print("\n1️⃣ PERMISSIONS DE LA LISTE:")
print("-"*40)

# Vérifier les permissions sur la liste
perms_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/effectivebasepermissions"

response = requests.get(perms_url, headers=headers)
print(f"Status permissions: {response.status_code}")

if response.status_code == 200:
    print("✅ J'ai accès aux permissions")
else:
    print(f"❌ Pas d'accès aux permissions: {response.text}")

print("\n2️⃣ QUI A CRÉÉ CES COMMANDES ?")
print("-"*40)

# Récupérer les 5 premières commandes avec créateur
items_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items?$select=Id,Title,Status,TargetVersion,Created,Author/Title&$expand=Author&$top=5"

response = requests.get(items_url, headers=headers)
print(f"Status items: {response.status_code}")

if response.status_code == 200:
    data = response.json()["d"]
    items = data.get("results", [])
    
    for item in items:
        author = item.get("Author", {}).get("Title", "Inconnu")
        print(f"  ID {item['Id']}: {item['Title']} - Status: {item['Status']} - Par: {author}")
else:
    print(f"❌ Impossible de récupérer les items: {response.text}")

print("\n3️⃣ TEST MODIFICATION SUR UN ITEM:")
print("-"*40)

# Essayer de modifier le premier item
if response.status_code == 200 and items:
    test_item = items[0]
    item_id = test_item['Id']
    
    print(f"Test sur item ID {item_id}: {test_item['Title']}")
    
    update_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items({item_id})"
    
    update_data = {
        "__metadata": {
            "type": "SP.Data.ATLASCommandsListItem"
        },
        "Status": "CANCELLED"
    }
    
    update_headers = headers.copy()
    update_headers["Content-Type"] = "application/json;odata=verbose"
    update_headers["IF-MATCH"] = "*"
    update_headers["X-HTTP-Method"] = "MERGE"
    
    print(f"URL: {update_url}")
    print(f"Data: {json.dumps(update_data, indent=2)}")
    print(f"Headers: {json.dumps(update_headers, indent=2)}")
    
    response = requests.post(update_url, headers=update_headers, json=update_data)
    
    print(f"\n📊 RÉSULTAT MODIFICATION:")
    print(f"Status Code: {response.status_code}")
    
    if response.status_code == 204:
        print("✅ SUCCÈS ! Je PEUX modifier les commandes !")
    else:
        print(f"❌ ÉCHEC ! Raison:")
        print(f"Headers de réponse: {dict(response.headers)}")
        print(f"Corps de réponse: {response.text}")
        
        # Essayer sans metadata
        print("\n🔄 TENTATIVE SANS METADATA:")
        update_data_simple = {"Status": "CANCELLED"}
        
        response2 = requests.post(update_url, headers=update_headers, json=update_data_simple)
        print(f"Status sans metadata: {response2.status_code}")
        
        if response2.status_code != 204:
            print(f"Échec aussi: {response2.text}")

print("\n" + "="*60)
print("🎯 CONCLUSION DU DIAGNOSTIC:")

if 'response' in locals() and response.status_code == 204:
    print("✅ JE PEUX NETTOYER LES COMMANDES !")
    print("   Problème résolu, prêt pour nettoyage complet")
else:
    print("❌ JE NE PEUX PAS NETTOYER")
    print("   Besoin d'analyser les erreurs ci-dessus")

print("="*60)