#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-shot setup of a remotely reachable, hardened OpenSSH Server on Windows 10/11 (Pro/Enterprise/Education).

.DESCRIPTION
    Installs and starts OpenSSH Server, opens the firewall ONLY for the sources you allow
    (default: Tailscale ranges + local subnet, not the internet), installs your public key
    with the correct file location and permissions (admin vs standard user), turns off
    password login once a key is in place, sets PowerShell as the default shell, optionally
    installs Tailscale, stops the PC from sleeping, and verifies everything at the end.
    Safe to re-run (idempotent).

.PARAMETER PublicKey
    One or more public keys: either the key text ("ssh-ed25519 AAAA... comment") or a path
    to a .pub file. Needed for key login; without it password login stays enabled.

.PARAMETER UserName
    Windows account that will log in over SSH. Default: the current user.

.PARAMETER AllowFrom
    Remote addresses allowed through the firewall on TCP/22.
    Default: Tailscale IPv4/IPv6 ranges and the local subnet.

.PARAMETER AllowFromAnywhere
    Allow port 22 from any address (NOT recommended; exposes SSH to the internet if routed).

.PARAMETER InstallTailscale
    Install Tailscale with winget (you still sign in once: "tailscale up").

.PARAMETER KeepPasswordAuth
    Do not disable password login even when a key was installed.

.PARAMETER SkipSleepFix
    Do not change the AC power sleep/hibernate timeouts.

.EXAMPLE
    .\Enable-SSHServer.ps1 -PublicKey "ssh-ed25519 AAAAC3... me@laptop" -InstallTailscale

.EXAMPLE
    .\Enable-SSHServer.ps1 -PublicKey C:\Users\me\Downloads\id_ed25519.pub -UserName bob

.NOTES
    Run in PowerShell as Administrator. Keep this file ASCII-only (Windows PowerShell 5.1).
#>
[CmdletBinding()]
param(
    [string[]]$PublicKey,
    [string]$UserName = $env:USERNAME,
    [string[]]$AllowFrom = @('100.64.0.0/10', 'fd7a:115c:a1e0::/48', 'LocalSubnet'),
    [switch]$AllowFromAnywhere,
    [switch]$InstallTailscale,
    [switch]$KeepPasswordAuth,
    [switch]$SkipSleepFix
)

$ErrorActionPreference = 'Stop'
$script:Warnings = New-Object System.Collections.Generic.List[string]

function Step($text) { Write-Host ""; Write-Host "=== $text ===" -ForegroundColor Cyan }
function Ok($text)   { Write-Host $text -ForegroundColor Green }
function Warn($text) { Write-Host "WARNING: $text" -ForegroundColor Yellow; $script:Warnings.Add($text) }
function Fail($text) { Write-Host "ERROR: $text" -ForegroundColor Red; exit 1 }

$sshdExe = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
$sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
$keyRegex = '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\s+[A-Za-z0-9+/=]+(\s.*)?$'

# ---------------------------------------------------------------- 1. Pre-checks
Step 'Step 1: Pre-checks (edition, account, keys)'
$edition = (Get-WindowsEdition -Online).Edition
Write-Host "Windows edition: $edition"
if ($edition -match '^Core' -or $edition -match 'Home') {
    Fail 'OpenSSH Server is not supported on Windows Home. Use Pro, Enterprise or Education.'
}

try { $userSid = (New-Object System.Security.Principal.NTAccount($UserName)).Translate([System.Security.Principal.SecurityIdentifier]) }
catch { Fail "User '$UserName' was not found on this machine." }

$isAdminUser = $false
try {
    $isAdminUser = [bool](Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { $_.SID -eq $userSid })
} catch {
    $isAdminUser = ($UserName -eq $env:USERNAME)   # elevated current user: assume admin
}
Write-Host ("Account: {0}  (SID {1}, {2})" -f $UserName, $userSid.Value, $(if ($isAdminUser) { 'Administrator' } else { 'standard user' }))

$localUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
if ($localUser -and -not $localUser.PasswordRequired) {
    Warn "Account '$UserName' has no password requirement. Set a password; passwordless accounts are unreliable over SSH."
}

# Parse and validate the supplied public keys
$keyLines = @()
foreach ($item in $PublicKey) {
    if ([string]::IsNullOrWhiteSpace($item)) { continue }
    if (Test-Path -LiteralPath $item -PathType Leaf) { $raw = Get-Content -LiteralPath $item } else { $raw = @($item) }
    foreach ($line in $raw) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -match $keyRegex) { $keyLines += $t } else { Warn "Ignored an invalid public key entry: '$($t.Substring(0, [Math]::Min(30, $t.Length)))...'" }
    }
}
if ($PublicKey -and $keyLines.Count -eq 0) { Fail 'No valid public key was found in -PublicKey. Aborting before changing anything.' }
if (-not $PublicKey) { Warn 'No -PublicKey given: password login will stay enabled (weaker). Re-run with -PublicKey to lock it down.' }

# ---------------------------------------------------------------- 2. Install OpenSSH
Step 'Step 2: Install OpenSSH Server and Client'
$caps = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' -or $_.Name -like 'OpenSSH.Client*' }
foreach ($cap in $caps) {
    if ($cap.State -eq 'Installed') { Ok "$($cap.Name) already installed."; continue }
    Write-Host "Installing $($cap.Name) ..."
    $wu = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($wu) {
        if ($wu.StartType -eq 'Disabled') { Set-Service -Name wuauserv -StartupType Manual }
        if ($wu.Status -ne 'Running') { Start-Service wuauserv }
    }
    try {
        Add-WindowsCapability -Online -Name $cap.Name | Out-Null
        Ok "$($cap.Name) installed."
    } catch {
        Warn "Add-WindowsCapability failed ($($_.Exception.Message)). Trying DISM ..."
        dism.exe /Online /Add-Capability /CapabilityName:$($cap.Name)
        if ($LASTEXITCODE -ne 0) {
            if ($cap.Name -like 'OpenSSH.Server*') { Fail 'Could not install OpenSSH Server. Install it from Settings > System > Optional features.' }
            Warn "Could not install $($cap.Name); continuing."
        } else { Ok "$($cap.Name) installed via DISM." }
    }
}
if (-not (Test-Path $sshdExe)) { Fail "sshd.exe not found at $sshdExe after install." }

# ---------------------------------------------------------------- 3. Service
Step 'Step 3: Start sshd and enable auto-start'
Set-Service -Name sshd -StartupType Automatic
if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }
Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
Ok 'sshd is running and set to Automatic (first start also generates host keys and sshd_config).'
if (-not (Test-Path $sshdConfig)) { Fail "$sshdConfig was not created. Check the sshd service." }

# ---------------------------------------------------------------- 4. Public key
Step 'Step 4: Install the public key for the account'
$keyInstalled = $false
if ($keyLines.Count -gt 0) {
    if ($isAdminUser) {
        $authFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
        Write-Host 'Administrator account: using administrators_authorized_keys (the per-user file is ignored for admins).'
    } else {
        $profilePath = if ($UserName -eq $env:USERNAME) { $env:USERPROFILE } else { Join-Path $env:SystemDrive "Users\$UserName" }
        if (-not (Test-Path $profilePath)) { Fail "Profile folder $profilePath not found. Log in as '$UserName' once, then re-run." }
        $authFile = Join-Path $profilePath '.ssh\authorized_keys'
    }
    $authDir = Split-Path $authFile
    if (-not (Test-Path $authDir)) { New-Item -ItemType Directory -Path $authDir -Force | Out-Null }

    $existing = @()
    if (Test-Path $authFile) { $existing = @(Get-Content $authFile | Where-Object { $_.Trim() }) }
    $have = @{}
    foreach ($e in $existing) { $p = $e -split '\s+'; if ($p.Count -ge 2) { $have["$($p[0]) $($p[1])"] = $true } }
    $added = 0
    foreach ($k in $keyLines) {
        $p = $k -split '\s+'
        if (-not $have.ContainsKey("$($p[0]) $($p[1])")) { $existing += $k; $have["$($p[0]) $($p[1])"] = $true; $added++ }
    }
    Set-Content -Path $authFile -Value $existing -Encoding ascii

    # Strict permissions: sshd ignores the file if others can write to it
    if ($isAdminUser) {
        icacls.exe $authFile /inheritance:r /grant '*S-1-5-18:F' /grant '*S-1-5-32-544:F' | Out-Null
    } else {
        icacls.exe $authFile /inheritance:r /grant '*S-1-5-18:F' /grant "*$($userSid.Value):F" | Out-Null
        icacls.exe $authDir  /inheritance:r /grant '*S-1-5-18:F' /grant "*$($userSid.Value):F" | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { Fail "icacls failed on $authFile; key auth would not work." }
    Ok "$added new key(s) added, $($keyLines.Count - $added) already present: $authFile"
    $keyInstalled = $true
}

# ---------------------------------------------------------------- 5. sshd_config hardening
Step 'Step 5: Harden sshd_config'
$disablePassword = $keyInstalled -and -not $KeepPasswordAuth
$begin = '# >>> Enable-SSHServer managed block >>>'
$end   = '# <<< Enable-SSHServer managed block <<<'
$block = @($begin, 'PubkeyAuthentication yes')
if ($disablePassword) { $block += 'PasswordAuthentication no' }
$block += @('PermitEmptyPasswords no', 'MaxAuthTries 4', 'LoginGraceTime 30', $end)

$backup = "$sshdConfig.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
Copy-Item $sshdConfig $backup
$text = [System.IO.File]::ReadAllText($sshdConfig)
$text = [regex]::Replace($text, "(?s)$([regex]::Escape($begin)).*?$([regex]::Escape($end))\r?\n?", '')
# Top of file on purpose: sshd uses the first value it sees, and the stock Match block sits at the end.
$newText = (($block -join "`r`n") + "`r`n`r`n" + $text.TrimStart())
[System.IO.File]::WriteAllText($sshdConfig, $newText, (New-Object System.Text.UTF8Encoding($false)))

& $sshdExe -t -f $sshdConfig
if ($LASTEXITCODE -ne 0) {
    Copy-Item $backup $sshdConfig -Force
    Fail "sshd_config failed validation; the original was restored from $backup."
}
Restart-Service sshd
Ok ("sshd_config updated (backup: {0}). Password login: {1}." -f $backup, $(if ($disablePassword) { 'DISABLED (key only)' } else { 'still enabled' }))

# ---------------------------------------------------------------- 6. Default shell
Step 'Step 6: Default SSH shell = PowerShell'
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
Ok 'Default shell set to Windows PowerShell.'

# ---------------------------------------------------------------- 7. Firewall
Step 'Step 7: Firewall rule for TCP/22'
$ruleName = 'OpenSSH-Server-In-TCP'
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName -DisplayName 'OpenSSH Server (sshd)' -Enabled True `
        -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
}
if ($AllowFromAnywhere) {
    Set-NetFirewallRule -Name $ruleName -Enabled True -Profile Any -RemoteAddress Any
    Warn 'Port 22 is open to ANY address. If this machine is internet-reachable, expect constant brute-force attempts.'
} else {
    # Scoped to Tailscale/LAN, so it is safe to apply on every network profile (incl. Public).
    Set-NetFirewallRule -Name $ruleName -Enabled True -Profile Any -RemoteAddress $AllowFrom
    Ok ("Port 22 allowed only from: {0} (all network profiles)." -f ($AllowFrom -join ', '))
}

# ---------------------------------------------------------------- 8. Tailscale
Step 'Step 8: Tailscale (private remote path, no port forwarding)'
$tsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
if (-not (Test-Path $tsExe) -and $InstallTailscale) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Tailscale.Tailscale -e --source winget --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { Warn 'winget could not install Tailscale. Install it from https://tailscale.com/download/windows' }
    } else { Warn 'winget not found. Install Tailscale from https://tailscale.com/download/windows' }
}
$tsIp = $null
if (Test-Path $tsExe) {
    try { $tsIp = (& $tsExe ip -4 2>$null | Select-Object -First 1) } catch { }
    if ($tsIp) { Ok "Tailscale is up. IPv4: $tsIp" }
    else { Warn "Tailscale is installed but not signed in. Run:  & '$tsExe' up   (sign in once, then re-check the IP)." }
} else {
    Warn 'Tailscale is not installed. Without it (or another private path) this PC is only reachable on the local network. Re-run with -InstallTailscale.'
}

# ---------------------------------------------------------------- 9. Power
Step 'Step 9: Keep the PC reachable (no sleep/hibernate on AC)'
if ($SkipSleepFix) { Write-Host 'Skipped (-SkipSleepFix).' }
else {
    powercfg.exe /change standby-timeout-ac 0
    powercfg.exe /change hibernate-timeout-ac 0
    Ok 'Sleep and hibernate on AC power set to Never. (On battery the PC may still sleep; laptop lid action is unchanged.)'
}

# ---------------------------------------------------------------- 10. Verify
Step 'Step 10: Verify'
Get-Service sshd | Format-Table Name, Status, StartType -AutoSize
$tcp = Test-NetConnection -ComputerName localhost -Port 22 -WarningAction SilentlyContinue
if ($tcp.TcpTestSucceeded) { Ok 'Port 22 is accepting connections locally.' } else { Warn 'Port 22 is NOT reachable locally. Check the sshd service.' }
try {
    $eff = & $sshdExe -T 2>$null | Select-String -Pattern '^(passwordauthentication|pubkeyauthentication|permitemptypasswords|maxauthtries) '
    Write-Host 'Effective sshd settings:'; $eff | ForEach-Object { Write-Host "  $($_.Line)" }
} catch { }

$lan = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '100.*' }).IPAddress
Write-Host ""
Write-Host '--- Connect from your other machine ---' -ForegroundColor Cyan
if ($tsIp) { Write-Host "  Tailscale : ssh $UserName@$tsIp" }
foreach ($ip in $lan) { Write-Host "  LAN       : ssh $UserName@$ip" }
if ($keyInstalled) { Write-Host '  (use the private key that matches the public key you supplied: ssh -i <key> ...)' }

if ($script:Warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Completed with $($script:Warnings.Count) warning(s):" -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} else {
    Write-Host ""
    Ok 'All done, no warnings.'
}
