# 3. Active Directory, DNS, DHCP et GPO

Scripts à lancer **sur DC01**, dans l'ordre, en PowerShell administrateur :

| Script | Effet |
|---|---|
| `01-Install-DC.ps1` | 1er lancement : nom, IP fixe, fuseau, redémarrage. 2e lancement : rôle AD DS et création de la forêt `ad.pmelab.fr` |
| `02-Configure-DnsDhcp.ps1` | redirecteur DNS vers pfSense, zones inverses, enregistrements des serveurs Linux, nettoyage DNS ; DHCP du VLAN 20 autorisé dans l'AD, options (passerelle, DNS, domaine), mise à jour DNS dynamique |
| `03-New-ADStructure.ps1` | OU, groupes AGDLP, comptes de test, **compte d'administration séparé**, politique de mots de passe + **PSO renforcée** pour les administrateurs, redirection des nouveaux ordinateurs vers `OU=Postes` |
| `04-New-GPOs.ps1` | 7 GPO créées et liées (voir ci-dessous) |
| `05-Install-Agents.ps1` | agents GLPI et Zabbix (manuel ou script de démarrage par GPO) |
| `06-Backup-SystemState.ps1 -Register` | sauvegarde quotidienne de l'état système du DC |

## Arborescence

```
ad.pmelab.fr
└── PME
    ├── Administration          comptes adm.* (Admins du domaine)
    ├── Utilisateurs
    │   ├── Direction · Comptabilite · Commercial · Informatique
    ├── Ordinateurs
    │   ├── Postes              ← nouveaux ordinateurs (redircmp)
    │   └── Serveurs
    ├── Groupes                 GG_* (rôles) · GL_* (ressources)
    ├── Comptes de service
    └── Desactives
```

## GPO

| GPO | Liée à | Effet | Vérification sur un poste |
|---|---|---|---|
| SEC - Verrouillage session | Utilisateurs | écran de veille protégé à 10 min | attendre 10 min |
| SEC - Stockage USB bloqué | Postes | lecture/écriture refusées sur les clés USB | brancher une clé |
| SEC - Pare-feu actif | Ordinateurs | pare-feu forcé sur les 3 profils + règle agent Zabbix | `Get-NetFirewallProfile` |
| SEC - Windows LAPS | Postes | mot de passe admin local unique, 16 car., rotation 30 j, chiffré dans l'AD | `Get-LapsADPassword CLIENT01 -AsPlainText` |
| MAJ - Windows Update | Ordinateurs | installation automatique le mercredi à 12 h | `gpresult /r` |
| USR - Lecteurs réseau | Utilisateurs | P: commun, S: compta selon le groupe | explorateur |
| ADM - Administrateurs locaux | Postes | `GG_Admins_Postes` dans les administrateurs locaux | `net localgroup Administrateurs` |

Diagnostic : `gpupdate /force`, `gpresult /h rapport.html`, et côté serveur *Group Policy Modeling*.

## Joindre un poste au domaine

```powershell
Add-Computer -DomainName ad.pmelab.fr -Credential PMELAB\adm.erwan -Restart
```

Le poste arrive dans `OU=Postes` et reçoit immédiatement les GPO, l'agent GLPI (inventaire) et l'agent Zabbix (supervision, enregistrement automatique).
