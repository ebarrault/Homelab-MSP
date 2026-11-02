<#
.SYNOPSIS
    Crée et lie les GPO du labo (idempotent).
.DESCRIPTION
    | GPO                          | Liée à            | Effet |
    |------------------------------|-------------------|-------|
    | SEC - Verrouillage session   | OU Utilisateurs   | écran verrouillé après 10 min |
    | SEC - Stockage USB bloqué    | OU Postes         | clés USB en lecture/écriture interdites |
    | SEC - Pare-feu actif         | OU Ordinateurs    | pare-feu Windows forcé sur les 3 profils |
    | SEC - Windows LAPS           | OU Postes         | mot de passe admin local unique, tourné tous les 30 j, sauvegardé dans l'AD |
    | MAJ - Windows Update         | OU Ordinateurs    | installation automatique le mercredi à 12 h |
    | USR - Lecteurs réseau        | OU Utilisateurs   | script d'ouverture de session : lecteurs P: et S: |
    | ADM - Administrateurs locaux | OU Postes         | GG_Admins_Postes ajouté aux administrateurs locaux |
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param([string]$CompanyOU = 'PME', [string]$FileServer = 'DC01')
$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy
$domain = Get-ADDomain
$base = "OU=$CompanyOU,$($domain.DistinguishedName)"
$ouUsers = "OU=Utilisateurs,$base"
$ouComputers = "OU=Ordinateurs,$base"
$ouPostes = "OU=Postes,$ouComputers"

function Get-OrCreateGpo([string]$Name, [string]$Comment, [string[]]$LinkTo) {
    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) { $gpo = New-GPO -Name $Name -Comment $Comment }
    foreach ($target in $LinkTo) {
        $linked = (Get-GPInheritance -Target $target).GpoLinks | Where-Object DisplayName -eq $Name
        if (-not $linked) { New-GPLink -Name $Name -Target $target -LinkEnabled Yes | Out-Null }
    }
    $gpo
}

# Après une modification directe de SYSVOL, il faut incrémenter la version de la GPO (AD + GPT.INI)
# pour que les clients la réappliquent. Partie utilisateur = 16 bits de poids fort.
function Update-GpoVersion($Gpo, [switch]$User) {
    $adPath = "CN={$($Gpo.Id)},CN=Policies,CN=System,$($domain.DistinguishedName)"
    $current = [int](Get-ADObject $adPath -Properties versionNumber).versionNumber
    $next = $current + $(if ($User) { 65536 } else { 1 })
    Set-ADObject $adPath -Replace @{ versionNumber = $next }
    $gptIni = "\\$($domain.DNSRoot)\SYSVOL\$($domain.DNSRoot)\Policies\{$($Gpo.Id)}\GPT.INI"
    (Get-Content $gptIni) -replace 'Version=\d+', "Version=$next" | Set-Content $gptIni
}

# --- Verrouillage de session (paramètres utilisateur) ---
$g = Get-OrCreateGpo 'SEC - Verrouillage session' 'Écran de veille protégé après 10 minutes' @($ouUsers)
$desk = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
Set-GPRegistryValue -Guid $g.Id -Key $desk -ValueName ScreenSaveActive -Type String -Value '1' | Out-Null
Set-GPRegistryValue -Guid $g.Id -Key $desk -ValueName ScreenSaverIsSecure -Type String -Value '1' | Out-Null
Set-GPRegistryValue -Guid $g.Id -Key $desk -ValueName ScreenSaveTimeOut -Type String -Value '600' | Out-Null
Set-GPRegistryValue -Guid $g.Id -Key $desk -ValueName SCRNSAVE.EXE -Type String -Value 'scrnsave.scr' | Out-Null

# --- Stockage USB amovible interdit ---
$g = Get-OrCreateGpo 'SEC - Stockage USB bloqué' 'Accès en lecture et écriture refusé aux disques amovibles' @($ouPostes)
$rs = 'HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'
Set-GPRegistryValue -Guid $g.Id -Key $rs -ValueName Deny_Read -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Guid $g.Id -Key $rs -ValueName Deny_Write -Type DWord -Value 1 | Out-Null

# --- Pare-feu Windows forcé ---
$g = Get-OrCreateGpo 'SEC - Pare-feu actif' 'Pare-feu activé sur les profils domaine, privé et public' @($ouComputers)
foreach ($p in 'DomainProfile', 'StandardProfile', 'PublicProfile') {
    Set-GPRegistryValue -Guid $g.Id -Key "HKLM\Software\Policies\Microsoft\WindowsFirewall\$p" -ValueName EnableFirewall -Type DWord -Value 1 | Out-Null
}
# Autorise l'agent Zabbix (10050/tcp) depuis le serveur de supervision uniquement
Set-GPRegistryValue -Guid $g.Id -Key 'HKLM\Software\Policies\Microsoft\WindowsFirewall\FirewallRules' -ValueName 'Zabbix-Agent' -Type String `
    -Value 'v2.30|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=10050|RA4=10.0.10.21|Name=Agent Zabbix|' | Out-Null

# --- Windows Update ---
$g = Get-OrCreateGpo 'MAJ - Windows Update' 'Installation automatique le mercredi à 12 h' @($ouComputers)
$wu = 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
Set-GPRegistryValue -Guid $g.Id -Key $wu -ValueName NoAutoUpdate -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Guid $g.Id -Key $wu -ValueName AUOptions -Type DWord -Value 4 | Out-Null           # télécharger et installer
Set-GPRegistryValue -Guid $g.Id -Key $wu -ValueName ScheduledInstallDay -Type DWord -Value 4 | Out-Null # mercredi
Set-GPRegistryValue -Guid $g.Id -Key $wu -ValueName ScheduledInstallTime -Type DWord -Value 12 | Out-Null

# --- Windows LAPS (intégré à Windows depuis avril 2023) ---
Update-LapsADSchema -Confirm:$false
Set-LapsADComputerSelfPermission -Identity $ouPostes | Out-Null
Set-LapsADReadPasswordPermission -Identity $ouPostes -AllowedPrincipals "$($domain.NetBIOSName)\GG_Lecteurs_LAPS" | Out-Null
$g = Get-OrCreateGpo 'SEC - Windows LAPS' 'Mot de passe administrateur local unique, sauvegardé dans AD' @($ouPostes)
$laps = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
Set-GPRegistryValue -Guid $g.Id -Key $laps -ValueName BackupDirectory -Type DWord -Value 2 | Out-Null        # 2 = Active Directory
Set-GPRegistryValue -Guid $g.Id -Key $laps -ValueName PasswordAgeDays -Type DWord -Value 30 | Out-Null
Set-GPRegistryValue -Guid $g.Id -Key $laps -ValueName PasswordLength -Type DWord -Value 16 | Out-Null
Set-GPRegistryValue -Guid $g.Id -Key $laps -ValueName PasswordComplexity -Type DWord -Value 4 | Out-Null
Set-GPRegistryValue -Guid $g.Id -Key $laps -ValueName ADPasswordEncryptionEnabled -Type DWord -Value 1 | Out-Null

# --- Lecteurs réseau : script d'ouverture de session déposé dans SYSVOL ---
$g = Get-OrCreateGpo 'USR - Lecteurs réseau' 'P: commun, S: service (selon les groupes)' @($ouUsers)
$scriptDir = "\\$($domain.DNSRoot)\SYSVOL\$($domain.DNSRoot)\Policies\{$($g.Id)}\User\Scripts\Logon"
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
@"
@echo off
rem Lecteurs réseau (généré par 04-New-GPOs.ps1)
net use P: \\$FileServer\Commun /persistent:no >nul 2>&1
whoami /groups | find /i "GG_Comptabilite" >nul && net use S: \\$FileServer\Compta /persistent:no >nul 2>&1
"@ | Set-Content -Path "$scriptDir\lecteurs.cmd" -Encoding Ascii
@"
[Logon]
0CmdLine=lecteurs.cmd
0Parameters=
"@ | Set-Content -Path (Join-Path (Split-Path $scriptDir) 'scripts.ini') -Encoding Unicode
# Déclare l'extension "Scripts" dans la GPO pour que le client la traite
$gpoAd = "CN={$($g.Id)},CN=Policies,CN=System,$($domain.DistinguishedName)"
Set-ADObject $gpoAd -Replace @{ gPCUserExtensionNames = '[{42B5FAAE-6536-11D2-AE5A-0000F87571E3}{40B66650-4972-11D1-A7CA-0000F87571E3}]' }
Update-GpoVersion $g -User

# --- Administrateurs locaux des postes (Restricted Groups via GptTmpl.inf) ---
$g = Get-OrCreateGpo 'ADM - Administrateurs locaux' 'GG_Admins_Postes membre des administrateurs locaux' @($ouPostes)
$sid = (Get-ADGroup GG_Admins_Postes).SID.Value
$secDir = "\\$($domain.DNSRoot)\SYSVOL\$($domain.DNSRoot)\Policies\{$($g.Id)}\Machine\Microsoft\Windows NT\SecEdit"
New-Item -ItemType Directory -Path $secDir -Force | Out-Null
@"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Group Membership]
*$sid`__Memberof = *S-1-5-32-544
*$sid`__Members =
"@ | Set-Content -Path "$secDir\GptTmpl.inf" -Encoding Unicode
$gpoAd = "CN={$($g.Id)},CN=Policies,CN=System,$($domain.DistinguishedName)"
Set-ADObject $gpoAd -Replace @{ gPCMachineExtensionNames = '[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]' }
Update-GpoVersion $g

Get-GPO -All | Where-Object DisplayName -match '^(SEC|MAJ|USR|ADM) - ' | Format-Table DisplayName, GpoStatus, ModificationTime
Write-Host 'Sur un poste : gpupdate /force puis gpresult /r pour vérifier.' -ForegroundColor Green
