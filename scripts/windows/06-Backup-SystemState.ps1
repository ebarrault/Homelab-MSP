<#
.SYNOPSIS
    Sauvegarde de l'état du système du contrôleur de domaine (AD, SYSVOL, registre) avec rétention.
.DESCRIPTION
    Complète la sauvegarde de la VM par Proxmox Backup Server : permet une restauration
    faisant autorité d'objets AD supprimés sans restaurer toute la machine.
    À planifier chaque nuit (voir -Register).
.EXAMPLE
    .\06-Backup-SystemState.ps1 -Target E: -Register
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$Target = 'E:',
    [int]$KeepVersions = 7,
    [switch]$Register
)
$ErrorActionPreference = 'Stop'
if (-not (Get-WindowsFeature Windows-Server-Backup).Installed) { Install-WindowsFeature Windows-Server-Backup | Out-Null }

if ($Register) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Target $Target -KeepVersions $KeepVersions"
    $trigger = New-ScheduledTaskTrigger -Daily -At 23:30
    Register-ScheduledTask -TaskName 'Sauvegarde état système AD' -Action $action -Trigger $trigger -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Write-Host 'Tâche planifiée créée (tous les jours à 23 h 30).'
    return
}

wbadmin start systemstatebackup -backupTarget:$Target -quiet
if ($LASTEXITCODE -ne 0) { throw "wbadmin a échoué (code $LASTEXITCODE)" }
# Rétention : ne garde que les N dernières versions
wbadmin delete systemstatebackup -keepVersions:$KeepVersions -quiet | Out-Null
Write-EventLog -LogName Application -Source 'Windows Backup' -EventId 9000 -EntryType Information `
    -Message "Sauvegarde état système OK vers $Target" -ErrorAction SilentlyContinue
