# 5. Zabbix

## Installation

Sur la VM Debian 12 `zabbix` (10.0.10.21) :

```bash
./scripts/linux/harden-debian.sh 80,443,10051
ZBX_DB_PASSWORD='…' ./scripts/linux/install-zabbix.sh
# après le changement du mot de passe Admin dans l'interface :
ZBX_URL=http://10.0.10.21/zabbix ZBX_PASSWORD='…' ./scripts/linux/zabbix-autoregistration.sh
```

## Ce qui est supervisé

| Hôte | Modèle | Exemples d'alertes |
|---|---|---|
| DC01 | *Windows by Zabbix agent active* + *Active Directory DS by Zabbix agent active* | service NTDS/DNS/DHCP arrêté, réplication, disque < 15 %, CPU > 90 % 5 min |
| CLIENT01/02 | *Windows by Zabbix agent active* (auto-enregistrés) | poste injoignable, disque plein, mises à jour en échec |
| GLPI, ZABBIX | *Linux by Zabbix agent active* + *Apache by HTTP* + *MySQL by Zabbix agent 2* | site HTTPS en erreur, base arrêtée, certificat qui expire |
| pfSense | *PFSense by SNMP* | interface WAN tombée, état des passerelles |
| Proxmox VE | *Proxmox VE by HTTP* (API, jeton en lecture seule) | VM arrêtée, stockage > 85 % |
| PBS | *Linux by Zabbix agent* + élément HTTP | datastore > 80 %, dernière sauvegarde de plus de 26 h |

## Enregistrement automatique

Les agents sont installés avec `HostMetadata=windows` (ou `linux`). Le script `zabbix-autoregistration.sh` crée, **via l'API JSON-RPC de Zabbix**, deux actions qui ajoutent automatiquement chaque nouvelle machine, la rangent dans son groupe et lui appliquent le bon modèle : un poste joint au domaine est supervisé quelques minutes plus tard, sans intervention.

## Alertes

*Alerts > Media types* : e-mail (SMTP) et webhook **Microsoft Teams** ou **Discord** ; utilisateur `Admin` abonné aux alertes de gravité *Average* et plus. Tableau de bord « Infrastructure » : carte du réseau, problèmes en cours, disponibilité.

## Test

Arrêter le service DHCP sur DC01 (`Stop-Service DHCPServer`) → problème *Service "DHCPServer" is not running* en moins d'une minute, notification reçue, puis résolution automatique au redémarrage du service.
