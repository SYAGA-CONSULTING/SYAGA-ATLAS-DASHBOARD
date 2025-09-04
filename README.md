# 🏛️ ATLAS v10.3 - FONDATION STABLE

Auto-update système for Windows servers with PowerShell agents.

## 🚀 Quick Start

**Installation via link generator:**
```powershell
# Generated from https://syaga-atlas.azurestaticapps.net
irm https://white-river-053fc6703.2.azurestaticapps.net/public/install-latest.ps1 | iex
```

## 📁 Current Files (v10.3 Foundation)

### Production Ready
- **`public/agent-v10.3.ps1`** - Stable agent (metrics collection)
- **`public/updater-v10.0.ps1`** - Stable updater (handles updates) 
- **`public/install-v10.0.ps1`** - Installs agent + updater + 2 tasks
- **`public/install-latest.ps1`** - Entry point (calls install-v10.0.ps1)

### Documentation
- **`FOUNDATION-v10.3.md`** - Complete foundation documentation
- **`archive/diagnostic-scripts/`** - Python diagnostic tools
- **`archive/versions-anciennes/`** - Archived old versions

## ✅ Validated Capabilities

- ✅ **Auto-update chain**: Claude → GitHub → Azure → SharePoint → Servers
- ✅ **3 servers tested**: SYAGA-VEEAM01, SYAGA-HOST01, SYAGA-HOST02  
- ✅ **Separate tasks**: Agent + Updater (no blocking)
- ✅ **SharePoint integration**: Metrics + logs + commands
- ✅ **Command cleanup**: Automated old command cancellation

## 🔄 Auto-Update Process

1. **Agent**: Collects metrics (CPU, Memory, Disk) every minute
2. **Updater**: Checks for UPDATE commands every minute  
3. **Commands**: Created in SharePoint list ATLAS-Commands
4. **Deployment**: Automatic via GitHub Actions → Azure Static Apps
5. **Rollback**: Future versions must be able to return to v10.3

## 🚨 Foundation Rules

- **v10.3 = SACRED** - Never modify these files
- **Rollback mandatory** - All v10.4+ must support rollback to v10.3
- **Test first** - Always test with diagnostic scripts before deploy
- **Separate tasks** - Never return to single-task architecture

## 🧠 Lessons Learned

### What Works ✅
- 2 separate PowerShell tasks (Agent + Updater)
- Python diagnostic scripts for testing
- SharePoint API without $orderby parameter
- JSON cleanup for duplicate keys
- Command cleanup before new deployments

### What Failed ❌ 
- Single agent modifying itself (freeze issues)
- Deploying without testing
- SharePoint queries with $orderby (returns 0)
- Multiple PENDING commands (updater confusion)
- Ignoring repeated user requests

---

**Last Update**: September 4, 2025  
**Status**: Production Ready  
**Next**: Rollback system implementation