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
        Write-Host "Failed to install OpenSSH Server. Exiting." -ForegroundColor Red
        exit 1
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
