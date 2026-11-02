<#
.SYNOPSIS
    Configure DNS (redirecteurs, zones inverses, nettoyage) et DHCP (étendue des postes, options, autorisation AD).
.NOTES
    Les postes sont dans le VLAN 20 : pfSense relaie leurs requêtes DHCP vers DC01 (Services > DHCP Relay).
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Forwarder = '10.0.10.1',           # Unbound sur pfSense
    [string]$DnsServer = '10.0.10.10',
    [string]$ScopeNetwork = '10.0.20.0',
    [string]$ScopeStart = '10.0.20.50',
    [string]$ScopeEnd = '10.0.20.200',
    [string]$ScopeGateway = '10.0.20.1'
)
$ErrorActionPreference = 'Stop'
$domain = (Get-ADDomain).DNSRoot

# ---------- DNS ----------
Set-DnsServerForwarder -IPAddress $Forwarder -UseRootHint $false
foreach ($net in '10.0.10.0/24', '10.0.20.0/24') {
    $reverse = (($net.Split('/')[0].Split('.')[0..2])[2..0] -join '.') + '.in-addr.arpa'
    if (-not (Get-DnsServerZone -Name $reverse -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -NetworkId $net -ReplicationScope Forest -DynamicUpdate Secure
        Write-Host "Zone inverse créée : $reverse"
    }
}
# Enregistrements des serveurs Linux (pas membres du domaine)
foreach ($r in @(@{ N = 'glpi'; IP = '10.0.10.20' }, @{ N = 'zabbix'; IP = '10.0.10.21' }, @{ N = 'pbs'; IP = '10.0.10.30' }, @{ N = 'pfsense'; IP = '10.0.10.1' })) {
    if (-not (Get-DnsServerResourceRecord -ZoneName $domain -Name $r.N -ErrorAction SilentlyContinue)) {
        Add-DnsServerResourceRecordA -ZoneName $domain -Name $r.N -IPv4Address $r.IP -CreatePtr
    }
}
# Nettoyage des enregistrements obsolètes (postes qui changent d'adresse)
Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 7.00:00:00 -ApplyOnAllZones
Set-DnsServerZoneAging -Name $domain -Aging $true

# ---------- DHCP ----------
if (-not (Get-WindowsFeature DHCP).Installed) { Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null }
# Groupes de sécurité DHCP + autorisation dans l'AD (sinon le service refuse de distribuer des baux)
netsh dhcp add securitygroups | Out-Null
Restart-Service DHCPServer
if (-not (Get-DhcpServerInDC | Where-Object IPAddress -eq $DnsServer)) {
    Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$domain" -IPAddress $DnsServer
}
# Supprime l'avertissement de configuration post-installation du Gestionnaire de serveur
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

if (-not (Get-DhcpServerv4Scope -ScopeId $ScopeNetwork -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4Scope -Name 'VLAN 20 - Postes' -StartRange $ScopeStart -EndRange $ScopeEnd `
        -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00 -State Active
}
Set-DhcpServerv4OptionValue -ScopeId $ScopeNetwork -Router $ScopeGateway -DnsServer $DnsServer -DnsDomain $domain
# Les postes enregistrent leurs noms dans le DNS, y compris pour les anciens clients
Set-DhcpServerv4DnsSetting -ScopeId $ScopeNetwork -DynamicUpdates Always -DeleteDnsRROnLeaseExpiry $true

Get-DhcpServerv4Scope | Format-Table ScopeId, Name, StartRange, EndRange, State
