# 4. GLPI

## Installation

Sur la VM Debian 12 `glpi` (10.0.10.20) :

```bash
./scripts/linux/harden-debian.sh 80,443
GLPI_DB_PASSWORD='…' ./scripts/linux/install-glpi.sh
```

Le script suit les recommandations de sécurité de GLPI : seul le dossier `public/` est servi par Apache, la configuration est dans `/etc/glpi`, les données dans `/var/lib/glpi`, les journaux dans `/var/log/glpi` ; HTTPS, cookies de session sécurisés, assistant d'installation supprimé, tâches automatiques par cron.

**Juste après l'installation** : changer les mots de passe de `glpi`, `tech`, `normal`, `post-only` (ou désactiver les trois derniers).

## Connexion à l'Active Directory

*Configuration > Authentification > Annuaires LDAP > Ajouter* :

| Champ | Valeur |
|---|---|
| Serveur | `10.0.10.10` (port 389, ou 636 en LDAPS après installation d'une autorité de certification) |
| BaseDN | `OU=PME,DC=ad,DC=pmelab,DC=fr` |
| DN du compte | `CN=svc_glpi,OU=Comptes de service,OU=PME,DC=ad,DC=pmelab,DC=fr` (compte de service en lecture seule) |
| Filtre de connexion | `(&(objectClass=user)(objectCategory=person)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))` — comptes actifs uniquement |
| Champ de l'identifiant | `samaccountname` |

Puis *Administration > Utilisateurs > Liaison annuaire LDAP > Importer de nouveaux utilisateurs*, et des **règles d'habilitation** : membres de `GG_Informatique` → profil *Technician*, tous les autres → *Self-Service*.

## Inventaire automatique

1. *Administration > Inventaire* : activer l'inventaire.
2. Déployer l'agent sur les postes avec `scripts/windows/05-Install-Agents.ps1` (script de démarrage d'ordinateur dans une GPO liée à `OU=Postes`).
3. Chaque poste remonte matériel, logiciels, système et utilisateur connecté toutes les 24 h.

## Tickets

- Catégories (Matériel, Logiciel, Comptes, Réseau), **SLA** (prise en charge 4 h, résolution 24 h en priorité moyenne), notifications par mail.
- Collecteur de mails (`support@…`) pour créer un ticket à partir d'un e-mail.
- Les utilisateurs se connectent avec leur compte AD sur l'interface simplifiée.
