# Plan d'adressage et dimensionnement

## Réseaux

| Réseau | Plage | Passerelle | Rôle |
|---|---|---|---|
| Box (WAN du labo) | 192.168.1.0/24 | 192.168.1.1 | accès Internet, administration de Proxmox |
| VLAN 10 — SERVEURS | 10.0.10.0/24 | 10.0.10.1 (pfSense) | services d'infrastructure, adresses fixes |
| VLAN 20 — POSTES | 10.0.20.0/24 | 10.0.20.1 (pfSense) | postes clients, DHCP fourni par DC01 via relais |
| VPN — ADMIN | 10.0.99.0/24 | 10.0.99.1 (pfSense) | administrateurs à distance (WireGuard) |

Domaine Active Directory : **`ad.pmelab.fr`** (NetBIOS `PMELAB`) — un sous-domaine d'un nom public, comme le recommande Microsoft (pas de `.local`).

## Adresses fixes

| Machine | VM | Adresse | Rôle |
|---|---|---|---|
| Proxmox VE | — | 192.168.1.10 | hyperviseur, interface https://192.168.1.10:8006 |
| pfSense | 100 | WAN 192.168.1.11 · 10.0.10.1 · 10.0.20.1 · 10.0.99.1 | pare-feu, NAT, DNS (Unbound), relais DHCP, VPN |
| DC01 | 110 | 10.0.10.10 | AD DS, DNS, DHCP, GPO, LAPS |
| GLPI | 120 | 10.0.10.20 | gestion de parc et tickets |
| ZABBIX | 121 | 10.0.10.21 | supervision |
| PBS | 130 | 10.0.10.30 | Proxmox Backup Server |
| CLIENT01 / CLIENT02 | 200 / 201 | DHCP 10.0.20.50-200 | postes Windows 11 joints au domaine |

## Dimensionnement

| VM | vCPU | RAM | Disque |
|---|---|---|---|
| pfSense | 2 | 2 Go | 16 Go |
| DC01 | 2 | 4 Go | 60 Go (+ 20 Go pour la sauvegarde d'état système) |
| GLPI | 2 | 2 Go | 32 Go |
| ZABBIX | 2 | 4 Go | 40 Go |
| PBS | 2 | 2 Go | 32 Go + 200 Go (datastore) |
| CLIENT01, CLIENT02 | 2 | 4 Go | 64 Go |
| **Total** | 14 | **22 Go** | ~570 Go |

Hôte conseillé : 6 cœurs / 32 Go de RAM / SSD 1 To. Avec 16 Go, démarrer un seul poste client et réduire Zabbix à 2 Go.
