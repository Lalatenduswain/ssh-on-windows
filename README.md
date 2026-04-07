# SSH on Windows

Enable and configure OpenSSH Server (sshd) on Windows 11 Pro using PowerShell.

## What's Included

| File | Description |
|------|-------------|
| `Enable-SSHServer.ps1` | PowerShell script to install, configure, and verify OpenSSH Server |
| `CLAUDE.md` | Claude Code context file with key SSH concepts and commands |

## Quick Start

1. Open **PowerShell as Administrator**
2. Allow script execution (if needed):
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
3. Run the script:
   ```powershell
   .\Enable-SSHServer.ps1
   ```

## What the Script Does

1. Installs OpenSSH Server (Windows optional feature)
2. Starts `sshd` service and sets it to auto-start on boot
3. Creates Windows Firewall rule for inbound TCP/22 (if missing)
4. Sets PowerShell as the default SSH shell
5. Verifies the service is running
6. Tests that port 22 is accepting connections

## Bonus: Install SSMS & Visual Studio via Winget

```powershell
# SQL Server Management Studio
winget install --id Microsoft.SQLServerManagementStudio --source winget --accept-package-agreements --accept-source-agreements

# Visual Studio 2022 Community
winget install --id Microsoft.VisualStudio.2022.Community --source winget --accept-package-agreements --accept-source-agreements
```

---

Created by [Lalatenduswain](https://github.com/Lalatenduswain)
