# SSH on Windows

Enable and configure OpenSSH Server (sshd) on Windows 11 Pro using PowerShell.

## What's Included

| File | Description |
|------|-------------|
| `Enable-SSHServer.ps1` | One script: install, harden and verify OpenSSH Server for remote access |
| [`MANUAL-SETUP.md`](MANUAL-SETUP.md) | The same setup done by hand, one checked step at a time (use it when the script fails or to find which step breaks) |

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
| 5 | `Test-Path : Illegal characters in path` right after Step 1 | Script bug: `-PublicKey` text was first tested as a file path, and Windows PowerShell 5.1 throws on characters such as `>` in the key comment | Fixed in commit `fba0b33`. The script now recognises key text before any path check. Re-download the script (see below) |
| 6 | Step 3: `Cannot start service sshd on computer '.'` (OpenSSH Server had installed fine in Step 2) | Generic Windows error. Usual causes: missing `C:\ProgramData\ssh` folder, `sshd_config` or host keys, wrong permissions on them, or port 22 already in use | Fixed in commit `ad61fbc`: the script now creates the folder and config, runs `ssh-keygen -A` and `FixHostFilePermissions.ps1`, and if sshd still cannot start it prints `sshd -t`, port 22 listeners and the OpenSSH event log. Manual repair is below |
| 7 | AnyDesk banner: "Free license (non-professional use). Session will be closed in 2 min" while the script was running | Free AnyDesk sessions are time limited | The script keeps running on the PC if AnyDesk drops. Reconnect and check the window; re-run the script if unsure, it is idempotent |

| 8 | Same Step 3 error again (`Enable-SSHServer.ps1:140 char:48`, plain `Start-Service sshd`) after the fix was pushed | The old copy of the script was still in the folder; the fixed file was never downloaded | Re-download and check the size (about 16.6 KB; the old copy is 14,822 bytes) before running. If the error does not mention `FixHostFilePermissions` or print diagnostics, it is the old file |
| 9 | Key was generated with `ssh-keygen` on the Windows PC and that public key was passed to `-PublicKey` | The key must come from the machine you connect **from**. A key pair created on the target only lets the PC log in to itself | On the client machine run `cat ~/.ssh/id_ed25519.pub` (Linux/macOS) or `type $env:USERPROFILE\.ssh\id_ed25519.pub` (Windows) and pass that line. Keep the private key on the client only |
| 10 | `whoami` showed `citpl-arsalan\administrator` (the built-in Administrator) while earlier runs were as `Arsalan` | Different elevated sessions use different accounts, and the script installs the key for the account running it unless `-UserName` is given | Pass `-UserName <account you will log in as>`. Both are admins and share `administrators_authorized_keys`, so the key works for either; prefer a named account over the built-in `Administrator` |

| 11 | Command run with the README placeholders left in: `-UserName <login account> ... -PublicKey` (no value) | Placeholders must be replaced. In PowerShell `<` is a redirection operator, so the line errors, and `-PublicKey` with no value runs without a key | Replace `<login account>` with the real account (e.g. `Arsalan`) and give `-PublicKey` the full one-line key in quotes. Several keys are allowed: `-PublicKey "ssh-ed25519 AAAA... a@x","ssh-rsa AAAA... b@y"` |
| 12 | AnyDesk "Session Closed: closed due to license limitations" | Free AnyDesk sessions end after a short time | Click Retry and reconnect; paste the download + run commands as one block so a session is enough. Once sshd and Tailscale are up, connect with SSH instead |

Which key to use: the public key (`.pub` file) of the machine you will connect **from**. On Linux/macOS print it with `cat ~/.ssh/id_ed25519.pub`; on Windows with `type $env:USERPROFILE\.ssh\id_ed25519.pub`. Never send the private key (the file without `.pub`).

Re-download the latest script on the Windows PC (elevated PowerShell):

```powershell
cd D:\0Lala
Invoke-WebRequest https://raw.githubusercontent.com/Lalatenduswain/ssh-on-windows/main/Enable-SSHServer.ps1 -OutFile .\Enable-SSHServer.ps1
(Get-Item .\Enable-SSHServer.ps1).Length    # about 16.6 KB means the new version
Unblock-File .\Enable-SSHServer.ps1
.\Enable-SSHServer.ps1 -UserName <login account> -InstallTailscale -PublicKey "<public key from the machine you connect FROM>"
```

Manual repair if `sshd` will not start:

```powershell
$o = "$env:SystemRoot\System32\OpenSSH"
& "$o\ssh-keygen.exe" -A
& "$o\FixHostFilePermissions.ps1" -Confirm:$false
Start-Service sshd; Get-Service sshd
# still failing? show the real reason:
& "$o\sshd.exe" -t
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 10 | Format-List TimeCreated, Message
Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue
```

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
| Target PC is Windows 10 22H2 (build 19045) | Windows 10 reached end of support in October 2025, so it only gets updates through the Extended Security Updates program | Keep SSH limited to Tailscale/LAN with password login off (the script's defaults), and plan an upgrade to Windows 11 |
| `Add-WindowsCapability` or the install stalls on a low-disk PC | The OpenSSH Server feature needs a few hundred MB free on `C:` | Free space first (Settings > System > Storage), then re-run |
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
