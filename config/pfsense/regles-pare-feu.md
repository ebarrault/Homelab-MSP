# Règles de pare-feu pfSense

## Alias (*Firewall > Aliases*)

| Alias | Type | Contenu |
|---|---|---|
| `DC` | Host | 10.0.10.10 |
| `GLPI` | Host | 10.0.10.20 |
| `ZABBIX` | Host | 10.0.10.21 |
| `RFC1918` | Network | 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 |
| `PORTS_AD` | Port | 53, 88, 123, 135, 389, 445, 464, 636, 3268, 3269, 49152:65535 |
| `PORTS_WEB` | Port | 80, 443 |
| `PORTS_ADMIN` | Port | 22, 3389, 443, 8006, 8007 |

## Interface POSTES (VLAN 20) — appliquées dans l'ordre

| # | Action | Proto | Source | Destination | Port | Pourquoi |
|---|---|---|---|---|---|---|
| 1 | Pass | TCP/UDP | POSTES net | `DC` | `PORTS_AD` | ouverture de session, GPO, DNS, Kerberos, LDAP, SMB (lecteurs réseau), heure |
| 2 | Pass | TCP | POSTES net | `GLPI` | 443 | agent GLPI, portail de tickets |
| 3 | Pass | TCP | POSTES net | `ZABBIX` | 10051 | agent Zabbix en mode actif |
| 4 | Block (journalisé) | any | POSTES net | `RFC1918` | any | **aucun autre accès aux réseaux internes** |
| 5 | Pass | TCP | POSTES net | any | `PORTS_WEB` | navigation Internet |
| 6 | Pass | UDP | POSTES net | POSTES address | 53 | résolution DNS via pfSense (secours) |
| — | *Block implicite* | | | | | tout le reste |

## Interface SERVEURS (VLAN 10)

| # | Action | Proto | Source | Destination | Port | Pourquoi |
|---|---|---|---|---|---|---|
| 1 | Pass | TCP | `ZABBIX` | any | 10050 | interrogation des agents (mode passif) |
| 2 | Pass | TCP/UDP | `DC` | SERVEURS address | 53 | redirecteur DNS vers Unbound |
| 3 | Pass | UDP | SERVEURS address | `DC` | 67 | relais DHCP vers DC01 |
| 4 | Pass | TCP/UDP | SERVEURS net | `DC` | `PORTS_AD` | serveurs Linux : LDAP (GLPI), NTP |
| 5 | Block (journalisé) | any | SERVEURS net | POSTES net | any | **un serveur compromis ne peut pas attaquer les postes** |
| 6 | Pass | TCP/UDP | SERVEURS net | !`RFC1918` | 53, 80, 123, 443 | mises à jour, téléchargements |

## Interface ADMIN_VPN (WireGuard)

| # | Action | Proto | Source | Destination | Port |
|---|---|---|---|---|---|
| 1 | Pass | TCP | ADMIN_VPN net | SERVEURS net | `PORTS_ADMIN` |
| 2 | Pass | TCP/UDP | ADMIN_VPN net | `DC` | `PORTS_AD` |
| 3 | Pass | TCP | ADMIN_VPN net | 192.168.1.10 | 8006 (Proxmox) |
| 4 | Pass | TCP | ADMIN_VPN net | POSTES net | 3389 (assistance à distance) |

## Interface WAN

| # | Action | Proto | Source | Destination | Port |
|---|---|---|---|---|---|
| 1 | Pass | UDP | any | WAN address | 51820 (WireGuard) |
| — | *Block implicite* | | | | |

## Test de la segmentation

Depuis CLIENT01 (`Test-NetConnection`) :

| Test | Attendu |
|---|---|
| `Test-NetConnection 10.0.10.10 -Port 389` | `TcpTestSucceeded : True` |
| `Test-NetConnection 10.0.10.20 -Port 443` | True |
| `Test-NetConnection 10.0.10.20 -Port 22` | **False** (SSH des serveurs interdit depuis les postes) |
| `Test-NetConnection 10.0.10.30 -Port 8007` | **False** (sauvegardes inaccessibles depuis les postes) |
| `Test-NetConnection 192.168.1.10 -Port 8006` | **False** (Proxmox inaccessible) |
