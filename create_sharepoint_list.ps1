# Script PowerShell pour créer la SharePoint List ATLAS
# Auteur: SYAGA Consulting
# Date: 2025-08-28

# Configuration
$SiteUrl = "https://syaga.sharepoint.com/sites/ATLAS"
$ListName = "ATLAS-Servers"

# Se connecter à SharePoint
Connect-PnPOnline -Url $SiteUrl -Interactive

# Créer la liste si elle n'existe pas
$list = Get-PnPList -Identity $ListName -ErrorAction SilentlyContinue
if (-not $list) {
    Write-Host "📋 Création de la liste $ListName..." -ForegroundColor Green
    New-PnPList -Title $ListName -Template GenericList
    $list = Get-PnPList -Identity $ListName
} else {
    Write-Host "✅ Liste $ListName existe déjà" -ForegroundColor Yellow
}

# Définir les colonnes
Write-Host "📊 Création des colonnes..." -ForegroundColor Green

$columns = @(
    @{Name="Hostname"; Type="Text"; Required=$true},
    @{Name="IPAddress"; Type="Text"; Required=$true},
    @{Name="Role"; Type="Choice"; Choices=@("Hyper-V Host","Backup Server","Domain Controller","Application Server")},
    @{Name="OperatingSystem"; Type="Text"},
    @{Name="State"; Type="Choice"; Choices=@("OK","WARNING","ERROR","OFFLINE")},
    @{Name="PendingUpdates"; Type="Number"; Default=0},
    @{Name="InstalledUpdates"; Type="Number"; Default=0},
    @{Name="FailedUpdates"; Type="Number"; Default=0},
    @{Name="LastContact"; Type="DateTime"},
    @{Name="RebootRequired"; Type="Boolean"; Default=$false},
    @{Name="HyperVStatus"; Type="Text"},
    @{Name="VeeamStatus"; Type="Choice"; Choices=@("Success","Warning","Failed","Unknown")},
    @{Name="CPUUsage"; Type="Number"; Default=0},
    @{Name="MemoryUsage"; Type="Number"; Default=0},
    @{Name="DiskSpaceGB"; Type="Number"; Default=0},
    @{Name="AgentInstalled"; Type="Boolean"; Default=$false},
    @{Name="AgentVersion"; Type="Text"},
    @{Name="LastUpdate"; Type="DateTime"},
    @{Name="Comments"; Type="Note"}
)

foreach ($col in $columns) {
    $existingField = Get-PnPField -List $ListName -Identity $col.Name -ErrorAction SilentlyContinue
    if (-not $existingField) {
        switch ($col.Type) {
            "Text" {
                Add-PnPField -List $ListName -DisplayName $col.Name -InternalName $col.Name -Type Text
            }
            "Number" {
                Add-PnPField -List $ListName -DisplayName $col.Name -InternalName $col.Name -Type Number
            }
            "Boolean" {
                Add-PnPField -List $ListName -DisplayName $col.Name -InternalName $col.Name -Type Boolean
            }
            "DateTime" {
                Add-PnPField -List $ListName -DisplayName $col.Name -InternalName $col.Name -Type DateTime
            }
            "Choice" {
                Add-PnPField -List $ListName -DisplayName $col.Name -InternalName $col.Name -Type Choice -Choices $col.Choices
            }
            "Note" {
                Add-PnPField -List $ListName -DisplayName $col.Name -InternalName $col.Name -Type Note
            }
        }
        Write-Host "  ✅ Colonne $($col.Name) créée" -ForegroundColor Green
    } else {
        Write-Host "  ⏭️ Colonne $($col.Name) existe déjà" -ForegroundColor Yellow
    }
}

Write-Host "`n🎉 Liste SharePoint ATLAS créée avec succès!" -ForegroundColor Green
Write-Host "📍 URL: $SiteUrl/Lists/$ListName" -ForegroundColor Cyan