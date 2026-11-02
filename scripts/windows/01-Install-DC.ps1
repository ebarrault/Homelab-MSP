<#
.SYNOPSIS
    Prépare DC01 et crée la forêt Active Directory (premier contrôleur de domaine, DNS intégré).
.DESCRIPTION
    Étape 1 (premier lancement) : nom, IP fixe, fuseau, redémarrage.
    Étape 2 (relancer après redémarrage) : rôle AD DS + promotion. Le serveur redémarre à la fin.
.EXAMPLE
    .\01-Install-DC.ps1 -DomainName ad.pmelab.fr -NetbiosName PMELAB
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ComputerName = 'DC01',
    [string]$IPAddress = '10.0.10.10',
    [int]$PrefixLength = 24,
    [string]$Gateway = '10.0.10.1',
    [string]$DomainName = 'ad.pmelab.fr',
    [string]$NetbiosName = 'PMELAB'
)
$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne $ComputerName) {
    $nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    if ($PSCmdlet.ShouldProcess($nic.Name, "IP fixe $IPAddress/$PrefixLength")) {
        Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
        New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
        # Le DC sera son propre DNS ; pfSense en attendant la promotion
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $Gateway
        Set-TimeZone -Id 'Romance Standard Time'
        Rename-Computer -NewName $ComputerName -Restart
    }
    return
}

if (-not (Get-WindowsFeature AD-Domain-Services).Installed) {
    Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
}

if (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain -and $PSCmdlet.ShouldProcess($DomainName, 'Créer la forêt')) {
    $dsrm = Read-Host -AsSecureString 'Mot de passe du mode restauration (DSRM)'
    Import-Module ADDSDeployment
    Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetbiosName `
        -ForestMode WinThreshold -DomainMode WinThreshold -InstallDns `
        -SafeModeAdministratorPassword $dsrm -NoRebootOnCompletion:$false -Force
}
