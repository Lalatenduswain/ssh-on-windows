# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This project contains scripts and documentation for enabling and configuring the OpenSSH Server (sshd) on Windows 11 Pro. It covers installation via PowerShell, firewall rules, service configuration, and key-based authentication setup.

## Repository Context

This is a subdirectory of a multi-project monorepo (`subha-jenkin-project`). Each subdirectory is an independent project. Work only within this directory unless explicitly asked otherwise.

## Key Windows SSH Concepts

- Windows 11 Pro includes OpenSSH Server as an optional feature (not installed by default)
- The SSH server config lives at `C:\ProgramData\ssh\sshd_config` (NOT `~/.ssh/`)
- The `administrators_authorized_keys` file controls key auth for admin users (separate from per-user `authorized_keys`)
- Windows Firewall rule "OpenSSH-Server-In-TCP" must allow inbound TCP/22
- The service name is `sshd` (display name: "OpenSSH SSH Server")

## Common PowerShell Commands

```powershell
# Install OpenSSH Server feature
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start and enable sshd
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

# Check firewall rule
Get-NetFirewallRule -Name *ssh*

# Create firewall rule if missing
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

# Test SSH locally
ssh localhost
```

## Default Shell Configuration

```powershell
# Set PowerShell as default SSH shell (instead of cmd.exe)
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```
