#!/usr/bin/env python3
"""
NETTOYAGE COMPLET - Garder SEULEMENT v10.2
"""
import requests
import base64

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
    "Content-Type": "application/json;odata=verbose"
}

# Liste des commandes
commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"

print("🧹 NETTOYAGE COMPLET - GARDER SEULEMENT v10.2")
print("="*60)

# Récupérer toutes les commandes PENDING
search_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items?$filter=Status eq 'PENDING'"

response = requests.get(search_url, headers=headers)

if response.status_code == 200:
    data = response.json()["d"]
    items = data.get("results", [])
    
    print(f"Trouvé {len(items)} commandes PENDING\n")
    
    kept = 0
    cancelled = 0
    
    for item in items:
        version = item.get('TargetVersion', 'unknown')
        title = item['Title']
        
        # Garder SEULEMENT v10.2
        if version == "10.2":
            print(f"✅ GARDÉE: {title} (v{version})")
            kept += 1
        else:
            # Annuler tout le reste
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
                print(f"❌ ANNULÉE: {title} (v{version})")
                cancelled += 1
            else:
                print(f"⚠️ Erreur: {title}")
    
    print(f"\n📊 RÉSULTAT:")
    print(f"   ✅ Gardées: {kept} commandes v10.2")
    print(f"   ❌ Annulées: {cancelled} anciennes commandes")
    print(f"   🎯 L'updater va maintenant trouver SEULEMENT v10.2 !")
    
else:
    print(f"❌ Erreur: {response.status_code}")

print("="*60)