<#
.SYNOPSIS
    Installe l'agent GLPI et l'agent Zabbix 2 (silencieux, idempotent).
    Utilisable en script de démarrage d'ordinateur par GPO, ou à la main.
.PARAMETER SourceShare
    Partage contenant les MSI (lecture pour "Ordinateurs du domaine"), ex. \\DC01\Deploiement$
#>
[CmdletBinding()]
param(
    [string]$SourceShare = '\\DC01\Deploiement$',
    [string]$GlpiServer = 'https://glpi.ad.pmelab.fr/',
    [string]$ZabbixServer = '10.0.10.21',
    [string]$LogFile = "$env:ProgramData\Deploiement\agents.log"
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
function Log($m) { Add-Content $LogFile ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) }

function Install-Msi([string]$Pattern, [string[]]$Arguments) {
    $msi = Get-ChildItem $SourceShare -Filter $Pattern | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $msi) { Log "MSI introuvable : $Pattern"; return }
    $p = Start-Process msiexec.exe -ArgumentList (@('/i', "`"$($msi.FullName)`"", '/qn', '/norestart') + $Arguments) -Wait -PassThru
    Log "$($msi.Name) : code retour $($p.ExitCode)"
}

# Agent GLPI : inventaire immédiat puis toutes les 24 h, en tant que service
if (-not (Get-Service glpi-agent -ErrorAction SilentlyContinue)) {
    Install-Msi 'GLPI-Agent-*-x64.msi' @("SERVER=$GlpiServer", 'RUNNOW=1', 'EXECMODE=1', 'ADD_FIREWALL_EXCEPTION=1', 'TAG=labo')
}

# Agent Zabbix 2 : mode actif (l'agent contacte le serveur) + passif depuis le serveur uniquement
if (-not (Get-Service 'Zabbix Agent 2' -ErrorAction SilentlyContinue)) {
    Install-Msi 'zabbix_agent2-*-windows-amd64-openssl.msi' @(
        "SERVER=$ZabbixServer", "SERVERACTIVE=$ZabbixServer", "HOSTNAME=$env:COMPUTERNAME",
        'HOSTMETADATA=windows', 'ENABLEPATH=1')
}
Log 'Terminé'
