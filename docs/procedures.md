# Procédures d'exploitation

Fiches courtes, comme dans un contrat d'infogérance : symptôme → diagnostic → résolution.

## Un utilisateur ne peut pas ouvrir de session

1. Compte verrouillé ? `Get-ADUser k.nguyen -Properties LockedOut, BadLogonCount, LastBadPasswordAttempt`
2. Origine du verrouillage : observateur d'événements du DC, **ID 4740** (poste à l'origine).
3. Déverrouiller : `Unlock-ADAccount k.nguyen` ; réinitialiser si besoin : `Set-ADAccountPassword k.nguyen -Reset` + changement à la prochaine connexion.
4. Message « relation d'approbation » : `Test-ComputerSecureChannel -Repair -Credential PMELAB\adm.erwan` sur le poste.
5. Clôturer le ticket GLPI avec la cause.

## Un poste ne reçoit pas d'adresse IP

1. Sur le poste : `ipconfig /all` (adresse en 169.254 = pas de réponse DHCP).
2. pfSense : *Status > Services* → relais DHCP démarré ; *Diagnostics > Packet Capture* sur POSTES, port 67.
3. DC01 : `Get-DhcpServerv4ScopeStatistics` (étendue pleine ?), service DHCPServer démarré (alerte Zabbix).

## Un service est en alerte dans Zabbix

1. Prendre en charge l'alerte (*Acknowledge*) avec un commentaire : le reste de l'équipe sait que c'est traité.
2. Ouvrir ou lier un ticket GLPI.
3. Après résolution, vérifier que l'alerte se ferme d'elle-même et noter la cause dans le ticket.

## Restaurer un fichier supprimé

PBS → sauvegarde de la VM concernée → *File Restore* → parcourir le disque → télécharger. Pas besoin de restaurer la VM.

## Récupérer le mot de passe administrateur local d'un poste

Membre de `GG_Lecteurs_LAPS` : `Get-LapsADPassword CLIENT01 -AsPlainText`, puis après l'intervention `Reset-LapsPassword` sur le poste pour le faire tourner.

## Ajouter un nouveau poste

1. Créer la VM (ou brancher le poste) dans le VLAN 20.
2. `Add-Computer -DomainName ad.pmelab.fr -Restart`.
3. Vérifier en 15 minutes : poste visible dans GLPI (inventaire) et dans Zabbix (auto-enregistrement), `gpresult /r` liste les GPO.

## Mise à jour mensuelle (Patch Tuesday)

| Étape | Quand |
|---|---|
| Postes : Windows Update automatique (GPO) | mercredi suivant le Patch Tuesday, 12 h |
| Serveurs Windows : manuel après la sauvegarde nocturne, un serveur à la fois | jeudi |
| Debian : `unattended-upgrades` pour la sécurité, `apt full-upgrade` mensuel | jeudi |
| pfSense, Proxmox, PBS : lecture des notes de version, mise à jour, test | mensuel |
