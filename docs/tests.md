# Page de tests

Cocher chaque test une fois vérifié.

| # | Test | Résultat attendu | OK |
|---|---|---|---|
| 1 | Interface Proxmox, vue des VM | 7 VM, ordre de démarrage configuré | ☐ |
| 2 | pfSense *Status > Interfaces* | WAN, SERVEURS, POSTES, ADMIN_VPN actives | ☐ |
| 3 | CLIENT01 `ipconfig /all` | 10.0.20.x, DNS 10.0.10.10, suffixe ad.pmelab.fr | ☐ |
| 4 | DC01 `Get-DhcpServerv4Lease -ScopeId 10.0.20.0` | baux de CLIENT01 et CLIENT02 | ☐ |
| 5 | `nslookup glpi` et `nslookup www.debian.org` depuis CLIENT01 | interne et externe résolus | ☐ |
| 6 | Ouverture de session `k.nguyen` sur CLIENT01 | session ouverte, lecteur P: présent | ☐ |
| 7 | `gpresult /r` sur CLIENT01 | les 7 GPO appliquées | ☐ |
| 8 | Clé USB sur CLIENT01 | accès refusé | ☐ |
| 9 | `Get-LapsADPassword CLIENT01 -AsPlainText` | mot de passe et date d'expiration | ☐ |
| 10 | Segmentation (`Test-NetConnection`, voir règles pfSense) | flux autorisés OK, flux interdits KO | ☐ |
| 11 | GLPI : connexion avec un compte AD | profil Self-Service | ☐ |
| 12 | GLPI : fiche de CLIENT01 | inventaire matériel + logiciels remontés par l'agent | ☐ |
| 13 | Zabbix : liste des hôtes | DC01, clients auto-enregistrés, Linux, pfSense, en vert | ☐ |
| 14 | Zabbix : arrêt du service DHCP | alerte en < 1 min, notification, résolution auto | ☐ |
| 15 | PBS : tâches de sauvegarde | dernière sauvegarde OK pour chaque VM | ☐ |
| 16 | Restauration de GLPI en VM 920 | VM démarrée, durée mesurée : ____ min (RTO) | ☐ |
| 17 | Restauration d'un utilisateur supprimé (corbeille AD) | compte et groupes rétablis | ☐ |
| 18 | Connexion WireGuard depuis l'extérieur | accès à DC01 en RDP, Proxmox 8006 | ☐ |
