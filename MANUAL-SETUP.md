# Manual OpenSSH Server Setup on Windows 10/11 Pro (no script)

Step-by-step setup for remote SSH access, done by hand in PowerShell. Use this when the
script `Enable-SSHServer.ps1` cannot be used, or to find out exactly which step fails.
Do one step at a time and only continue when the check at the end of the step is good.

Reference machine: Windows 10 Pro 22H2 (build 19045), OpenSSH Server already installed
as an optional feature, remote path through Tailscale, key-only login.

## Before you start

- Open **PowerShell as Administrator** (Start > type `PowerShell` > right-click > Run as
  administrator). The title bar must start with `Administrator:`.
- Check the account you are using: `whoami`. Both the built-in `Administrator` and a named
  admin account work. Admin accounts share one key file (Step 4).
- Have the **public key** (`.pub` line) of the machine you will connect **from**:
  `cat ~/.ssh/id_ed25519.pub` (Linux/macOS) or `type $env:USERPROFILE\.ssh\id_ed25519.pub`
  (Windows). Never use or send the private key. A key created on the target PC only lets
  that PC log in to itself.
- Remote desktop tools with time limits (for example free AnyDesk) can close the session
  mid-task. Keep each session short; once Tailscale and SSH work, connect with SSH instead.

## Step 1: Check the current state (read-only)

```powershell
Get-Service sshd | Format-List Name, Status, StartType
Test-Path "$env:ProgramData\ssh"
Test-Path "$env:ProgramData\ssh\sshd_config"
Get-ChildItem "$env:ProgramData\ssh" -ErrorAction SilentlyContinue | Select-Object Name, Length
```

What to look for:

| Output | Meaning |
|--------|---------|
| `Get-Service` says it cannot find `sshd` | OpenSSH Server is not installed. Install it (Step 1b) |
| Folder or `sshd_config` is `False` | Missing, so sshd cannot start. Step 2 creates it |
| No `ssh_host_*_key` files listed | Host keys missing. Step 2 generates them |

Step 1b (only if the service does not exist):

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

Needs internet/Windows Update access and a few hundred MB free on `C:`.

## Step 2: Make sshd start

Common reasons `Start-Service sshd` fails with "Cannot start service sshd on computer '.'":
missing `C:\ProgramData\ssh` folder, missing `sshd_config`, missing host keys, wrong
permissions, or port 22 already in use.

```powershell
$o = "$env:SystemRoot\System32\OpenSSH"
New-Item -ItemType Directory -Path "$env:ProgramData\ssh" -Force | Out-Null
if (-not (Test-Path "$env:ProgramData\ssh\sshd_config")) { Copy-Item "$o\sshd_config_default" "$env:ProgramData\ssh\sshd_config" }
& "$o\ssh-keygen.exe" -A
& "$o\FixHostFilePermissions.ps1" -Confirm:$false
Set-Service sshd -StartupType Automatic
Start-Service sshd
Get-Service sshd
```

Good result: `Status` is `Running`.

If it still fails, collect the real reason:

```powershell
& "$o\sshd.exe" -t
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 10 | Format-List TimeCreated, Message
Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue
```

- `sshd -t` prints a config error: fix that line in `C:\ProgramData\ssh\sshd_config`.
- Something already listens on port 22: stop that program or change the port.
- Permission errors in the event log: re-run `FixHostFilePermissions.ps1`.

## Step 3: Firewall (Tailscale and local subnet only)

```powershell
if (-not (Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (sshd)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null }
Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -Enabled True -Profile Any -RemoteAddress 100.64.0.0/10,LocalSubnet
Get-NetFirewallRule -Name OpenSSH-Server-In-TCP | Get-NetFirewallAddressFilter
```

Good result: `RemoteAddress` shows `100.64.0.0/10` and `LocalSubnet`, not `Any`. Do not open
port 22 to the internet.

## Step 4: Install the public key

Admin accounts read `C:\ProgramData\ssh\administrators_authorized_keys` (the per-user
`~\.ssh\authorized_keys` is ignored for admins). Standard users use
`C:\Users\<name>\.ssh\authorized_keys`.

```powershell
$f = "$env:ProgramData\ssh\administrators_authorized_keys"
Add-Content -Path $f -Value '<paste the full one-line public key here>' -Encoding ascii
icacls.exe $f /inheritance:r /grant '*S-1-5-18:F' /grant '*S-1-5-32-544:F'
icacls.exe $f
```

Good result: only `SYSTEM` and `Administrators` are listed. Wrong permissions make sshd
ignore the file silently.

## Step 5: Tailscale (private remote path)

```powershell
# run the installer (downloaded from https://tailscale.com/download/windows)
D:\0Lala\tailscale-setup-<version>.exe
& "$env:ProgramFiles\Tailscale\tailscale.exe" up
& "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4
```

Sign in in the browser when asked, then note the `100.x.x.x` address. Both machines must
be on the same tailnet (or the Windows PC shared to yours).

## Step 6: Test key login before locking anything

From the machine you connect from:

```bash
ssh <account>@100.x.x.x
```

Good result: you are logged in without a password prompt. If it asks for a password, key
login is not working yet. Do **not** continue to Step 7; check the key file, its
permissions, the account name, and `Get-WinEvent -LogName 'OpenSSH/Operational'`.

## Step 7: Turn off password login (only after Step 6 works)

```powershell
$c = "$env:ProgramData\ssh\sshd_config"
Copy-Item $c "$c.bak"
$t = Get-Content $c -Raw
Set-Content $c -Value ("PasswordAuthentication no`r`nPubkeyAuthentication yes`r`n`r`n" + $t) -Encoding ascii
& "$env:SystemRoot\System32\OpenSSH\sshd.exe" -t
Restart-Service sshd
```

The lines go at the **top** of the file on purpose: sshd uses the first value it finds, and
the stock `Match Group administrators` block near the end would otherwise override them.
If `sshd -t` prints an error, restore before restarting:
`Copy-Item "$c.bak" $c -Force`.

Lock-out recovery: log in at the console or via remote desktop, restore `sshd_config.bak`,
`Restart-Service sshd`.

## Optional: keep the PC reachable

```powershell
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
```

Applies to AC power only (add `-dc` variants for battery).

## Final checks

```powershell
Get-Service sshd
& "$env:SystemRoot\System32\OpenSSH\sshd.exe" -T | Select-String 'passwordauthentication|pubkeyauthentication'
Get-NetFirewallRule -Name OpenSSH-Server-In-TCP | Get-NetFirewallAddressFilter
```

Expected: `Running`, `passwordauthentication no`, `pubkeyauthentication yes`, firewall scoped to
Tailscale and the local subnet.

See also the automated route and the issue table in [README.md](README.md).
