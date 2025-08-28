#!/usr/bin/env python3
import subprocess
import time
from datetime import datetime

print(f"📸 CAPTURE SCREENSHOT - {datetime.now().strftime('%H:%M')}")

# Méthode 1: Avec Chrome headless
timestamp = datetime.now().strftime("%H%M%S")
output_path = f"/mnt/c/temp/dashboard_{timestamp}.png"

cmd = [
    "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe",
    "--headless",
    "--disable-gpu",
    "--window-size=1920,1080",
    "--screenshot=" + output_path,
    "https://white-river-053fc6703.2.azurestaticapps.net"
]

try:
    print("🌐 Lancement Chrome headless...")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    print(f"✅ Screenshot sauvé: {output_path}")
    print(f"📁 Ouvre: C:\\temp\\dashboard_{timestamp}.png")
except Exception as e:
    print(f"❌ Erreur: {e}")
    
# Alternative avec Edge
print("\n🔄 Alternative avec Edge...")
edge_cmd = f'/mnt/c/Windows/System32/cmd.exe /c "start msedge --headless --disable-gpu --window-size=1920,1080 --screenshot=C:\\temp\\edge_{timestamp}.png https://white-river-053fc6703.2.azurestaticapps.net"'
subprocess.run(edge_cmd, shell=True)
print(f"📁 Edge screenshot: C:\\temp\\edge_{timestamp}.png")

print("\n🎯 Screenshots disponibles dans C:\\temp\\")