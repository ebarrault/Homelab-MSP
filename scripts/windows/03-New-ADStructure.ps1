<#
.SYNOPSIS
    Arborescence d'OU, groupes (AGDLP), comptes d'administration séparés et comptes de test.
.NOTES
    Pour la gestion des arrivées/départs en production, voir le projet 05-automatisation-ad.
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param([string]$CompanyOU = 'PME')
$ErrorActionPreference = 'Stop'
$dn = (Get-ADDomain).DistinguishedName
$upn = (Get-ADDomain).DNSRoot
# Nom du groupe « Admins du domaine » quelle que soit la langue du système (RID 512)
$domainAdmins = (Get-ADGroup -Identity "$((Get-ADDomain).DomainSID)-512").Name

function New-OU([string]$Name, [string]$Path) {
    $target = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$target'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
    }
    $target
}

$root = New-OU $CompanyOU $dn
$users = New-OU 'Utilisateurs' $root
$computers = New-OU 'Ordinateurs' $root
$null = New-OU 'Postes' $computers
$null = New-OU 'Serveurs' $computers
$groups = New-OU 'Groupes' $root
$admins = New-OU 'Administration' $root
$null = New-OU 'Desactives' $root
$null = New-OU 'Comptes de service' $root
foreach ($s in 'Direction', 'Comptabilite', 'Commercial', 'Informatique') { $null = New-OU $s $users }

# Les nouveaux ordinateurs joints au domaine arrivent dans l'OU Postes (et reçoivent donc les GPO)
redircmp "OU=Postes,$computers" | Out-Null

# Groupes : GG = rôles (globaux), GL = ressources (domaine local)
$groupList = @(
    @{ N = 'GG_Tous'; S = 'Global' }, @{ N = 'GG_Direction'; S = 'Global' }, @{ N = 'GG_Comptabilite'; S = 'Global' },
    @{ N = 'GG_Commercial'; S = 'Global' }, @{ N = 'GG_Informatique'; S = 'Global' },
    @{ N = 'GG_Admins_Postes'; S = 'Global' },          # administrateurs locaux des postes (via GPO)
    @{ N = 'GG_Lecteurs_LAPS'; S = 'Global' },          # peuvent lire le mot de passe LAPS
    @{ N = 'GL_Partage_Commun_RW'; S = 'DomainLocal' }, @{ N = 'GL_Partage_Compta_RW'; S = 'DomainLocal' }
)
foreach ($g in $groupList) {
    if (-not (Get-ADGroup -Filter "Name -eq '$($g.N)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $g.N -GroupScope $g.S -GroupCategory Security -Path $groups
    }
}
Add-ADGroupMember GL_Partage_Commun_RW -Members GG_Tous
Add-ADGroupMember GL_Partage_Compta_RW -Members GG_Comptabilite
Add-ADGroupMember GG_Admins_Postes -Members GG_Informatique
Add-ADGroupMember GG_Lecteurs_LAPS -Members GG_Informatique

# Compte d'administration séparé du compte de travail (bonne pratique : jamais d'admin pour lire ses mails)
function New-LabUser($Sam, $First, $Last, $Path, $Groups, [switch]$Admin) {
    if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) { return }
    $pwd = Read-Host -AsSecureString "Mot de passe initial pour $Sam"
    New-ADUser -Name "$First $Last$(if ($Admin) { ' (admin)' })" -SamAccountName $Sam -UserPrincipalName "$Sam@$upn" `
        -GivenName $First -Surname $Last -Path $Path -AccountPassword $pwd -Enabled $true -ChangePasswordAtLogon (-not $Admin)
    foreach ($g in $Groups) { Add-ADGroupMember $g -Members $Sam }
}
New-LabUser 'adm.erwan' 'Erwan' 'ADMIN' $admins @($domainAdmins) -Admin
New-LabUser 'k.nguyen' 'Kevin' 'Nguyen' "OU=Informatique,$users" @('GG_Tous', 'GG_Informatique')
New-LabUser 'e.lefevre' 'Elodie' 'Lefevre' "OU=Comptabilite,$users" @('GG_Tous', 'GG_Comptabilite')
New-LabUser 's.martin' 'Sophie' 'Martin' "OU=Commercial,$users" @('GG_Tous', 'GG_Commercial')

# Politique de mots de passe du domaine + politique renforcée (PSO) pour les comptes d'administration
Set-ADDefaultDomainPasswordPolicy -Identity $upn -MinPasswordLength 12 -ComplexityEnabled $true `
    -MaxPasswordAge 365.00:00:00 -PasswordHistoryCount 12 -LockoutThreshold 5 `
    -LockoutDuration 00:15:00 -LockoutObservationWindow 00:15:00
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'PSO-Administrateurs'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy -Name 'PSO-Administrateurs' -Precedence 10 -MinPasswordLength 16 -ComplexityEnabled $true `
        -PasswordHistoryCount 24 -MaxPasswordAge 180.00:00:00 -LockoutThreshold 3 -LockoutDuration 00:30:00 `
        -LockoutObservationWindow 00:30:00 -ReversibleEncryptionEnabled $false
    Add-ADFineGrainedPasswordPolicySubject 'PSO-Administrateurs' -Subjects $domainAdmins
}
# Compte de service en lecture seule pour la liaison LDAP de GLPI
if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc_glpi'" -ErrorAction SilentlyContinue)) {
    $pwd = Read-Host -AsSecureString 'Mot de passe du compte de service svc_glpi (long et aléatoire)'
    New-ADUser -Name 'svc_glpi' -SamAccountName 'svc_glpi' -UserPrincipalName "svc_glpi@$upn" `
        -Path "OU=Comptes de service,$root" -AccountPassword $pwd -Enabled $true -PasswordNeverExpires $true `
        -CannotChangePassword $true -Description 'Liaison LDAP GLPI (lecture seule)'
}

# Partages : Commun (tous), Compta (comptabilité), Deploiement$ (MSI des agents, lecture pour les ordinateurs)
$sharesRoot = 'C:\Partages'
$netbios = (Get-ADDomain).NetBIOSName
$shares = @(
    @{ Name = 'Commun'; Group = 'GL_Partage_Commun_RW'; Right = 'Modify' },
    @{ Name = 'Compta'; Group = 'GL_Partage_Compta_RW'; Right = 'Modify' },
    @{ Name = 'Deploiement$'; Group = 'Ordinateurs du domaine'; Right = 'ReadAndExecute' }
)
foreach ($sh in $shares) {
    $path = Join-Path $sharesRoot ($sh.Name.TrimEnd('$'))
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    $group = if ($sh.Group -eq 'Ordinateurs du domaine') { (Get-ADGroup -Identity "$((Get-ADDomain).DomainSID)-515").Name } else { $sh.Group }
    # NTFS : héritage coupé, Administrateurs + SYSTEM en contrôle total, groupe de ressource avec le droit prévu
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($id in 'S-1-5-32-544', 'S-1-5-18') {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier $id), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    }
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$netbios\$group", $sh.Right, 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -Path $path -AclObject $acl
    # Partage : utilisateurs authentifiés en modification, la restriction réelle est portée par NTFS
    if (-not (Get-SmbShare -Name $sh.Name -ErrorAction SilentlyContinue)) {
        # Noms des comptes intégrés traduits depuis leur SID (indépendant de la langue)
        $authUsers = (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-11').Translate([System.Security.Principal.NTAccount]).Value
        $localAdmins = (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value
        New-SmbShare -Name $sh.Name -Path $path -ChangeAccess $authUsers -FullAccess $localAdmins -FolderEnumerationMode AccessBased | Out-Null
    }
}

Write-Host 'Structure AD prête.' -ForegroundColor Green
