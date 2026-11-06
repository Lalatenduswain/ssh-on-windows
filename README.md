# SSH on Windows

Enable and configure OpenSSH Server (sshd) on Windows 11 Pro using PowerShell.

## What's Included

| File | Description |
|------|-------------|
| `Enable-SSHServer.ps1` | One script: install, harden and verify OpenSSH Server for remote access |

## Quick Start

1. On your **other machine**, create a key if you have none: `ssh-keygen -t ed25519` (copy the `.pub` text).
2. On the Windows PC, open **PowerShell as Administrator**:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\Enable-SSHServer.ps1 -PublicKey "ssh-ed25519 AAAA... me@laptop" -InstallTailscale
   ```
3. Sign in to Tailscale once (`tailscale up`), then connect: `ssh <user>@<tailscale-ip>`.

## Parameters

| Parameter | Purpose |
|-----------|---------|
| `-PublicKey` | Key text or path to a `.pub` file (several allowed). Enables key login and, unless `-KeepPasswordAuth`, disables password login |
| `-UserName` | Windows account to log in as (default: current user) |
| `-AllowFrom` | Firewall sources for TCP/22 (default: Tailscale ranges + local subnet) |
| `-AllowFromAnywhere` | Open port 22 to any address (not recommended) |
| `-InstallTailscale` | Install Tailscale via winget |
| `-KeepPasswordAuth` | Leave password login enabled |
| `-SkipSleepFix` | Do not change AC sleep/hibernate timeouts |

## What the Script Does

1. Checks edition (not Home), the account, and validates your public key before changing anything
2. Installs OpenSSH Server + Client (DISM fallback), starts `sshd`, auto-start on boot
3. Installs the key in the right place with correct permissions (`administrators_authorized_keys` for admins, `~\.ssh\authorized_keys` otherwise)
4. Hardens `sshd_config` (key auth, no empty passwords, password login off once a key is in), validated with `sshd -t` and auto-restored on error
5. Sets PowerShell as the default SSH shell
6. Limits the firewall rule to Tailscale/LAN sources (all network profiles)
7. Optionally installs Tailscale and shows the IP
8. Stops AC sleep/hibernate so the PC stays reachable
9. Verifies the service, port 22 and effective settings, and prints the connect commands

The script is safe to re-run.

## Bonus: Install SSMS & Visual Studio via Winget

```powershell
# SQL Server Management Studio
winget install --id Microsoft.SQLServerManagementStudio --source winget --accept-package-agreements --accept-source-agreements

# Visual Studio 2022 Community
winget install --id Microsoft.VisualStudio.2022.Community --source winget --accept-package-agreements --accept-source-agreements
```

---

Created by [Lalatenduswain](https://github.com/Lalatenduswain)
