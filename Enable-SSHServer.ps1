#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enables and configures OpenSSH Server on Windows 11 Pro.
.DESCRIPTION
    Installs OpenSSH Server, starts the service, configures auto-start,
    sets up the firewall rule, and sets PowerShell as the default SSH shell.
.NOTES
    Run this script in PowerShell as Administrator.
#>

Write-Host "=== Pre-requisite 1: Check Windows Edition ===" -ForegroundColor Cyan
$edition = (Get-WindowsEdition -Online).Edition
Write-Host "Detected Windows Edition: $edition"
if ($edition -match 'Core|Home') {
    Write-Host "OpenSSH Server is NOT available on Windows Home edition. You need Pro, Enterprise, or Education." -ForegroundColor Red
    exit 1
} else {
    Write-Host "Windows edition is supported." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Pre-requisite 2: Ensure Windows Update service is running ===" -ForegroundColor Cyan
$wuauserv = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
if ($wuauserv) {
    if ($wuauserv.Status -ne 'Running') {
        Write-Host "Starting Windows Update service (required for feature install)..."
        Set-Service -Name wuauserv -StartupType Manual
        Start-Service wuauserv
        Write-Host "Windows Update service started." -ForegroundColor Green
    } else {
        Write-Host "Windows Update service is already running." -ForegroundColor Green
    }
} else {
    Write-Host "Windows Update service not found. OpenSSH install may fail." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Pre-requisite 3: Install OpenSSH Client ===" -ForegroundColor Cyan
$sshClient = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
if ($sshClient.State -eq 'Installed') {
    Write-Host "OpenSSH Client is already installed." -ForegroundColor Green
} else {
    Write-Host "Installing OpenSSH Client..."
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
    if ($?) {
        Write-Host "OpenSSH Client installed." -ForegroundColor Green
    } else {
        Write-Host "Failed to install OpenSSH Client. Continuing anyway..." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Pre-requisite 4: Check Network Profile ===" -ForegroundColor Cyan
$publicNets = Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' }
if ($publicNets) {
    Write-Host "WARNING: Active network is set to 'Public'. Inbound SSH may be blocked." -ForegroundColor Yellow
    Write-Host "To fix, run: Set-NetConnectionProfile -Name '$($publicNets[0].Name)' -NetworkCategory Private" -ForegroundColor Yellow
} else {
    Write-Host "Network profile is Private/Domain. SSH inbound will work." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Step 1: Install OpenSSH Server ===" -ForegroundColor Cyan
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -eq 'Installed') {
    Write-Host "OpenSSH Server is already installed." -ForegroundColor Green
} else {
    Write-Host "Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    if ($?) {
        Write-Host "OpenSSH Server installed successfully." -ForegroundColor Green
    } else {
        Write-Host "Add-WindowsCapability failed. Trying DISM as fallback..." -ForegroundColor Yellow
        dism /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0
        if ($LASTEXITCODE -eq 0) {
            Write-Host "OpenSSH Server installed via DISM." -ForegroundColor Green
        } else {
            Write-Host "Both methods failed. Install manually: Settings > System > Optional Features > OpenSSH Server." -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host ""
Write-Host "=== Step 2: Start and auto-enable the sshd service ===" -ForegroundColor Cyan
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
Write-Host "sshd service started and set to Automatic." -ForegroundColor Green

Write-Host ""
Write-Host "=== Step 3: Configure firewall rule ===" -ForegroundColor Cyan
$firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($firewallRule) {
    Write-Host "Firewall rule already exists." -ForegroundColor Green
} else {
    Write-Host "Creating firewall rule for SSH (TCP/22)..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
        -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22
    Write-Host "Firewall rule created." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Step 4: Set PowerShell as default SSH shell ===" -ForegroundColor Cyan
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" `
    -Name DefaultShell `
    -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -PropertyType String -Force | Out-Null
Write-Host "Default SSH shell set to PowerShell." -ForegroundColor Green

Write-Host ""
Write-Host "=== Step 5: Verify sshd service status ===" -ForegroundColor Cyan
Get-Service sshd | Format-Table Name, Status, StartType -AutoSize

Write-Host ""
Write-Host "=== Step 6: Test SSH connection ===" -ForegroundColor Cyan
$tcpTest = Test-NetConnection -ComputerName localhost -Port 22
if ($tcpTest.TcpTestSucceeded) {
    Write-Host "SSH port 22 is open and accepting connections." -ForegroundColor Green
} else {
    Write-Host "SSH port 22 is NOT reachable. Check the service and firewall." -ForegroundColor Red
}
