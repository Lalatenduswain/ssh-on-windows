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

## Issues We Faced (and the fix)

| # | What happened | Cause | Fix |
|---|---------------|-------|-----|
| 1 | `Security warning ... Do you want to run Enable-SSHServer.ps1? [D] Do not run [R] Run once` | The file was downloaded or copied from another machine, so Windows marks it as "from the internet" | Run `Unblock-File .\Enable-SSHServer.ps1` once, or answer `R` |
| 2 | `cannot be run because it contains a "#requires" statement for running as Administrator` (`ScriptRequiresElevation`) | PowerShell was opened normally, not elevated. Nothing was changed on the PC | Start > type `PowerShell` > right-click > **Run as administrator**. The title bar must say "Administrator: Windows PowerShell" |
| 3 | Example command pasted with the placeholder key `"ssh-ed25519 AAAA... me@laptop"` | The README example was copied without replacing the key | Use your real public key line (`cat ~/.ssh/id_ed25519.pub` or `type $env:USERPROFILE\.ssh\id_rsa.pub`). The script validates the key first and aborts before changing anything if it is invalid |
| 4 | Script file path had a zero in the folder name (`D:\0Lala`) | Easy to mistype as the letter O | Use Tab completion for paths |

Working sequence (elevated PowerShell):

```powershell
cd D:\0Lala
Unblock-File .\Enable-SSHServer.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Enable-SSHServer.ps1 -PublicKey "ssh-ed25519 AAAA...your real key... user@host" -InstallTailscale
```

## Issues We May Face Next

| Symptom | Likely cause | What to do |
|---------|--------------|------------|
| `Permission denied (publickey)` although the key was added | The private key on the client does not match the public key given to the script, or you connect as a different Windows user | Use `ssh -i <private key> <user>@<ip>`; confirm `-UserName` is the account you log in as |
| Key login ignored for an Administrator account | Admins read `C:\ProgramData\ssh\administrators_authorized_keys`, not `~\.ssh\authorized_keys`; wrong ACLs also make sshd skip it | The script handles both. To check: `icacls C:\ProgramData\ssh\administrators_authorized_keys` should list only SYSTEM and Administrators |
| `Connection timed out` over Tailscale | Tailscale not signed in on one side, or the PC is asleep | Run `& "$env:ProgramFiles\Tailscale\tailscale.exe" up`, then `tailscale status` on both machines. Keep sleep on AC set to Never |
| `Connection timed out` on the LAN or internet | The firewall rule only allows Tailscale and the local subnet (by design) | Use the Tailscale IP, or pass `-AllowFrom '<your IP/range>'`. Avoid `-AllowFromAnywhere` |
| Tailscale installed but no IP printed | First sign-in is interactive | Run `tailscale up`, sign in in the browser, then re-run the script to see the connect lines |
| `winget` not found or the Tailscale install fails | Old Windows build or missing App Installer | Install Tailscale from https://tailscale.com/download/windows, then re-run |
| `Add-WindowsCapability` fails (error 0x800f0954 / 0x800f0950) | Machine uses WSUS or blocks Features on Demand, or no internet | Allow access to Windows Update, or install via Settings > System > Optional features > OpenSSH Server; the script falls back to DISM first |
| Script stops with "not supported on Windows Home" | OpenSSH Server needs Pro, Enterprise or Education | Upgrade the edition, or use another remote tool |
| Locked out after password login was turned off | Key does not match, or a different user was used | Log in at the console or via RDP, then restore the backup: `Copy-Item C:\ProgramData\ssh\sshd_config.bak-<timestamp> C:\ProgramData\ssh\sshd_config -Force; Restart-Service sshd`. Or re-run the script with `-KeepPasswordAuth` |
| `sshd_config failed validation` | A manual edit conflicts with the managed block | The script restores the backup itself. Fix the line reported by `sshd -t -f C:\ProgramData\ssh\sshd_config` |
| Windows account has no password | Passwordless accounts are unreliable over SSH | Set a password on the account first |
| Antivirus or endpoint tools flag the script or block sshd | Security software policy | Allow `C:\Windows\System32\OpenSSH\sshd.exe` and the script path |
| PC reachable only while plugged in | The sleep fix applies to AC power only | Set `powercfg /change standby-timeout-dc 0` if it must stay on battery, and check the lid-close action |

Useful checks after a run:

```powershell
Get-Service sshd
& "$env:SystemRoot\System32\OpenSSH\sshd.exe" -T | Select-String 'passwordauthentication|pubkeyauthentication'
Get-NetFirewallRule -Name OpenSSH-Server-In-TCP | Get-NetFirewallAddressFilter
Get-WinEvent -LogName OpenSSH/Operational -MaxEvents 20 | Format-List TimeCreated, Message
```

## Bonus: Install SSMS & Visual Studio via Winget

```powershell
# SQL Server Management Studio
winget install --id Microsoft.SQLServerManagementStudio --source winget --accept-package-agreements --accept-source-agreements

# Visual Studio 2022 Community
winget install --id Microsoft.VisualStudio.2022.Community --source winget --accept-package-agreements --accept-source-agreements
```

---

Created by [Lalatenduswain](https://github.com/Lalatenduswain)
