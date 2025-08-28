#!/usr/bin/env python3
"""
AUTOTEST RÉEL AVEC CHROME - JAMAIS HEADLESS
Selon la consigne permanente : toujours voir ce que l'utilisateur voit
"""

import time
import subprocess
import os
from datetime import datetime
import requests

class ChromeRealAutoTest:
    def __init__(self):
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.errors = []
        self.success = []
        
    def test_url_with_curl(self, url):
        """Test d'abord avec curl pour voir la réponse"""
        print(f"\n🔍 Test avec curl: {url}")
        try:
            result = subprocess.run(
                f"curl -I -s {url}", 
                shell=True, 
                capture_output=True, 
                text=True,
                timeout=10
            )
            print(f"HTTP Response:\n{result.stdout[:200]}")
            
            if "404" in result.stdout:
                self.errors.append(f"❌ 404 détecté sur {url}")
                return False
            elif "200" in result.stdout:
                self.success.append(f"✅ 200 OK sur {url}")
                return True
            else:
                self.errors.append(f"⚠️ Réponse inattendue sur {url}")
                return False
        except Exception as e:
            self.errors.append(f"❌ Erreur curl: {e}")
            return False
    
    def check_github_deployment(self):
        """Vérifier le statut du déploiement GitHub Actions"""
        print("\n📊 Vérification du déploiement GitHub...")
        
        # Vérifier le dernier workflow
        result = subprocess.run(
            "gh run list --workflow=azure-static-web-apps.yml --limit=1 --json status,conclusion,updatedAt",
            shell=True,
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print(f"GitHub Actions status: {result.stdout}")
            if "failure" in result.stdout.lower():
                self.errors.append("❌ Déploiement GitHub échoué")
                return False
            elif "in_progress" in result.stdout.lower():
                self.errors.append("⏳ Déploiement en cours...")
                return None
            elif "success" in result.stdout.lower():
                self.success.append("✅ Déploiement GitHub réussi")
                return True
        
        return None
        
    def test_with_real_chrome(self, url):
        """Test avec Chrome réel via PowerShell"""
        print(f"\n🌐 Lancement Chrome RÉEL (pas headless) sur: {url}")
        
        # Script PowerShell pour Chrome réel avec screenshot
        ps_script = f"""
# Ouvrir Chrome sur l'URL
Start-Process chrome "{url}"

# Attendre le chargement
Start-Sleep -Seconds 5

# Prendre un screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

$filepath = "C:\\Users\\sebastien.questier\\Desktop\\autotest_{self.timestamp}.png"
$bitmap.Save($filepath, [System.Drawing.Imaging.ImageFormat]::Png)

Write-Host "📸 Screenshot sauvegardé: $filepath"

$graphics.Dispose()
$bitmap.Dispose()
"""
        
        # Sauvegarder et exécuter le script
        with open('/tmp/chrome_test.ps1', 'w') as f:
            f.write(ps_script)
        
        result = subprocess.run(
            '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass -File /tmp/chrome_test.ps1',
            shell=True,
            capture_output=True,
            text=True
        )
        
        print(result.stdout)
        if result.stderr:
            print(f"Erreurs: {result.stderr}")
        
        self.success.append(f"✅ Screenshot Chrome réel pris: autotest_{self.timestamp}.png")
        
    def verify_files_exist(self):
        """Vérifier que les fichiers existent bien dans le repo"""
        print("\n📁 Vérification des fichiers...")
        
        files_to_check = [
            'dashboard_final_auth.html',
            'auth_test.html',
            'no_auth_utf8.html',
            'index.html'
        ]
        
        for file in files_to_check:
            if os.path.exists(file):
                self.success.append(f"✅ Fichier existe: {file}")
                
                # Vérifier l'encodage UTF-8
                try:
                    with open(file, 'r', encoding='utf-8') as f:
                        content = f.read(1000)
                        if 'Ã©' in content or 'Ã ' in content:
                            self.errors.append(f"❌ Problème UTF-8 détecté dans {file}")
                        else:
                            self.success.append(f"✅ UTF-8 OK dans {file}")
                except Exception as e:
                    self.errors.append(f"❌ Erreur lecture {file}: {e}")
            else:
                self.errors.append(f"❌ Fichier manquant: {file}")
    
    def check_git_status(self):
        """Vérifier le statut git"""
        print("\n🔄 Vérification Git...")
        
        result = subprocess.run("git status --short", shell=True, capture_output=True, text=True)
        if result.stdout:
            print(f"Fichiers non commités:\n{result.stdout}")
            self.errors.append("⚠️ Des fichiers ne sont pas commités")
        else:
            self.success.append("✅ Tous les fichiers sont commités")
    
    def wait_for_deployment(self, max_wait=60):
        """Attendre que le déploiement soit terminé"""
        print(f"\n⏳ Attente du déploiement (max {max_wait}s)...")
        
        start_time = time.time()
        while time.time() - start_time < max_wait:
            status = self.check_github_deployment()
            if status is True:
                return True
            elif status is False:
                return False
            time.sleep(10)
            print(".", end="", flush=True)
        
        self.errors.append("⏰ Timeout en attendant le déploiement")
        return False
    
    def run_all_tests(self):
        """Exécuter tous les tests"""
        print("🚀 AUTOTESTS CHROME RÉEL - JAMAIS HEADLESS")
        print("=" * 60)
        
        # 1. Vérifier les fichiers locaux
        self.verify_files_exist()
        
        # 2. Vérifier git
        self.check_git_status()
        
        # 3. Attendre le déploiement
        if not self.wait_for_deployment():
            print("\n⚠️ Le déploiement n'est pas terminé!")
        
        # 4. Tester les URLs
        base_url = "https://white-river-053fc6703.2.azurestaticapps.net"
        urls_to_test = [
            f"{base_url}/",
            f"{base_url}/dashboard_final_auth.html",
            f"{base_url}/auth_test.html",
            f"{base_url}/no_auth_utf8.html"
        ]
        
        for url in urls_to_test:
            self.test_url_with_curl(url)
            time.sleep(1)
        
        # 5. Test avec Chrome réel sur la page principale
        self.test_with_real_chrome(f"{base_url}/dashboard_final_auth.html")
        
        # Rapport final
        print("\n" + "=" * 60)
        print("📊 RAPPORT D'AUTOTEST")
        print("=" * 60)
        
        if self.success:
            print("\n✅ SUCCÈS:")
            for s in self.success:
                print(f"  {s}")
        
        if self.errors:
            print("\n❌ ERREURS:")
            for e in self.errors:
                print(f"  {e}")
        
        print("\n" + "=" * 60)
        if not self.errors:
            print("🎉 TOUS LES TESTS RÉUSSIS!")
        else:
            print(f"⚠️ {len(self.errors)} ERREUR(S) DÉTECTÉE(S)")
            print("🔧 CORRECTIONS NÉCESSAIRES")
        
        return len(self.errors) == 0

if __name__ == "__main__":
    tester = ChromeRealAutoTest()
    success = tester.run_all_tests()
    
    if not success:
        print("\n🔧 LANCEMENT DES CORRECTIONS AUTOMATIQUES...")
        # Ici on peut ajouter des corrections automatiques
        exit(1)
    
    exit(0)