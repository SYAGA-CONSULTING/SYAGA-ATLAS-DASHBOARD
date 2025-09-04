#!/usr/bin/env python3
"""
URGENT : Nettoyer les vieilles commandes PENDING
"""
import requests
import base64

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

print("\n🧹 NETTOYAGE DES ANCIENNES COMMANDES PENDING")
print("="*60)

# Récupérer toutes les commandes PENDING
search_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items?$filter=Status eq 'PENDING'&$select=Id,Title,TargetVersion,Status"

response = requests.get(search_url, headers=headers)

if response.status_code == 200:
    data = response.json()["d"]
    items = data.get("results", [])
    
    print(f"Trouvé {len(items)} commandes PENDING:\n")
    
    for item in items:
        print(f"  - {item['Title']} (v{item.get('TargetVersion')}) - ID: {item['Id']}")
        
        # Annuler toutes les commandes SAUF v10.1
        if item.get('TargetVersion') != "10.1":
            update_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items({item['Id']})"
            
            update_data = {
                "__metadata": {
                    "type": "SP.Data.ATLASCommandsListItem"
                },
                "Status": "CANCELLED"
            }
            
            update_headers = headers.copy()
            update_headers["IF-MATCH"] = "*"
            update_headers["X-HTTP-Method"] = "MERGE"
            
            response = requests.post(update_url, headers=update_headers, json=update_data)
            
            if response.status_code == 204:
                print(f"    ❌ ANNULÉE (ancienne version)")
            else:
                print(f"    ⚠️ Erreur annulation: {response.status_code}")
        else:
            print(f"    ✅ GARDÉE (v10.1)")
    
    print("\n" + "="*60)
    print("✅ NETTOYAGE TERMINÉ")
    print("Seules les commandes v10.1 restent PENDING")
    
else:
    print(f"❌ Erreur: {response.status_code}")

print("="*60)