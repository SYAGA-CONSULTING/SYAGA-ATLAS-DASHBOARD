#!/usr/bin/env python3
"""
TEST COMPLET DU SYSTÈME ROLLBACK
1. Déploie version défectueuse
2. Vérifie l'échec
3. Déclenche rollback
4. Vérifie retour à v10.3
"""
import requests
import base64
import time

# Config SharePoint
tenant_id = "6027d81c-ad9b-48f5-9da6-96f1bad11429"
client_id = "f7c4f1b2-3380-4e87-961f-09922ec452b4"
client_secret_b64 = "Z3Y0OFF+NHRkakY2RE9td1ZXSS5UdXJNcVcwaGJZZEpGRS5aeWFvaw=="
client_secret = base64.b64decode(client_secret_b64).decode('utf-8')

def get_token():
    token_url = f"https://accounts.accesscontrol.windows.net/{tenant_id}/tokens/OAuth/2"
    token_body = {
        "grant_type": "client_credentials",
        "client_id": f"{client_id}@{tenant_id}",
        "client_secret": client_secret,
        "resource": f"00000003-0000-0ff1-ce00-000000000000/syagacons.sharepoint.com@{tenant_id}"
    }
    response = requests.post(token_url, data=token_body)
    return response.json()["access_token"]

def create_command(title, command_type, version):
    token = get_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json;odata=verbose", 
        "Content-Type": "application/json;odata=verbose"
    }
    
    command_data = {
        "__metadata": {"type": "SP.Data.ATLASCommandsListItem"},
        "Title": title,
        "CommandType": command_type,
        "TargetHostname": "ALL",
        "TargetVersion": version,
        "Status": "PENDING",
        "CreatedBy": "Claude_ROLLBACK_TEST"
    }
    
    commands_list_id = "ce76b316-0d45-42e3-9eda-58b90b3ca4c5"
    create_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{commands_list_id}')/items"
    
    response = requests.post(create_url, headers=headers, json=command_data)
    return response.status_code == 201

def check_agent_versions():
    """Récupère les versions actuelles des agents"""
    token = get_token()
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json;odata=nometadata"}
    
    servers_list_id = "94dc7ad4-740f-4c1f-b99c-107e01c8f70b"
    logs_url = f"https://syagacons.sharepoint.com/_api/web/lists(guid'{servers_list_id}')/items?$filter=Hostname eq 'SYAGA-VEEAM01' or Hostname eq 'SYAGA-HOST01' or Hostname eq 'SYAGA-HOST02'&$select=Hostname,AgentVersion,LastContact&$top=10"
    
    response = requests.get(logs_url, headers=headers)
    
    if response.status_code == 200:
        items = response.json().get("value", [])
        versions = {}
        for item in items:
            hostname = item.get("Hostname")
            version = item.get("AgentVersion")
            if hostname:
                versions[hostname] = version
        return versions
    return {}

print("🧪 TEST COMPLET SYSTÈME ROLLBACK")
print("="*60)

print("\n1️⃣ ÉTAT INITIAL (v10.3):")
versions = check_agent_versions()
for host, version in versions.items():
    print(f"   {host}: v{version}")

print("\n2️⃣ DÉPLOIEMENT VERSION DÉFECTUEUSE (v10.4):")
if create_command("UPDATE_v10.4_BROKEN_TEST", "UPDATE", "10.4"):
    print("✅ Commande UPDATE v10.4 créée")
    print("⏳ Attendre 2 minutes pour voir l'échec...")
    time.sleep(120)
    
    print("\n3️⃣ VÉRIFICATION ÉCHEC:")
    versions_after = check_agent_versions()
    failed = False
    for host, version in versions_after.items():
        print(f"   {host}: v{version}")
        if version == "10.4":
            print(f"      ❌ {host} en v10.4 - Probablement en échec")
            failed = True
    
    if failed:
        print("\n4️⃣ DÉCLENCHEMENT ROLLBACK:")
        if create_command("ROLLBACK_TO_v10.3_AUTO", "ROLLBACK", "10.3"):
            print("✅ Commande ROLLBACK créée")
            print("⏳ Attendre 2 minutes pour rollback...")
            time.sleep(120)
            
            print("\n5️⃣ VÉRIFICATION ROLLBACK:")
            versions_final = check_agent_versions()
            rollback_success = True
            for host, version in versions_final.items():
                print(f"   {host}: v{version}")
                if version != "10.3":
                    print(f"      ❌ {host} pas revenu en v10.3")
                    rollback_success = False
                else:
                    print(f"      ✅ {host} rollback réussi")
            
            if rollback_success:
                print("\n🎊 SUCCÈS TOTAL: SYSTÈME ROLLBACK FONCTIONNEL")
            else:
                print("\n❌ ÉCHEC: Rollback incomplet")
        else:
            print("❌ Impossible de créer commande rollback")
    else:
        print("⚠️ Aucun serveur n'a basculé en v10.4")
else:
    print("❌ Impossible de créer commande UPDATE")

print("="*60)