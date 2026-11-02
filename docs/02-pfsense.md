# 2. pfSense

## Interfaces

| Interface | Carte | VLAN | Adresse | Services |
|---|---|---|---|---|
| WAN | vtnet0 (vmbr0) | — | 192.168.1.11/24, passerelle 192.168.1.1 | NAT sortant |
| SERVEURS | vtnet1 | 10 | 10.0.10.1/24 | DNS Resolver |
| POSTES | vtnet1 | 20 | 10.0.20.1/24 | DNS Resolver, **relais DHCP → 10.0.10.10** |
| ADMIN_VPN | tun_wg0 | — | 10.0.99.1/24 | WireGuard |

*Interfaces > Assignments > VLANs* : créer les VLAN 10 et 20 sur `vtnet1`, puis les assigner.

> Le WAN est dans le réseau privé de la box : décocher **Block private networks** et **Block bogon networks** sur l'interface WAN (sinon tout le trafic de la box est rejeté).

## DNS et DHCP

- **DNS Resolver (Unbound)** actif sur SERVEURS et POSTES, avec un *Domain Override* : `ad.pmelab.fr` → `10.0.10.10`. DC01 utilise pfSense comme redirecteur pour Internet ; pfSense renvoie vers DC01 pour le domaine.
- **Serveur DHCP désactivé** sur toutes les interfaces : c'est DC01 qui distribue les baux.
- **DHCP Relay** (*Services > DHCP Relay*) : interface POSTES, serveur de destination `10.0.10.10`.

## Règles de pare-feu

Détail complet et alias : [`config/pfsense/regles-pare-feu.md`](../config/pfsense/regles-pare-feu.md). Principe : **tout est refusé entre VLAN**, seuls les flux nécessaires sont ouverts, du plus précis au plus général.

## Accès d'administration à distance : WireGuard

1. *System > Package Manager* : installer **WireGuard**.
2. *VPN > WireGuard > Tunnels* : `tun_wg0`, port **51820**, adresse `10.0.99.1/24`, générer les clés.
3. *Peers* : un pair par administrateur (clé publique du client, *Allowed IPs* `10.0.99.2/32`).
4. Assigner `tun_wg0` (interface ADMIN_VPN), règle WAN : `UDP 51820` vers *WAN address*.
5. Sur la box : redirection du port UDP 51820 vers 192.168.1.11.

Configuration du client :

```ini
[Interface]
PrivateKey = <clé privée du client>
Address = 10.0.99.2/32
DNS = 10.0.10.10

[Peer]
PublicKey = <clé publique de pfSense>
Endpoint = <IP publique de la box>:51820
AllowedIPs = 10.0.10.0/24, 10.0.20.0/24, 10.0.99.0/24
PersistentKeepalive = 25
```

## Durcissement et exploitation

- Interface web en HTTPS uniquement, accessible depuis ADMIN_VPN et SERVEURS (règle *anti-lockout* désactivée une fois les règles en place).
- Compte `admin` renommé/désactivé au profit d'un compte nominatif.
- *Diagnostics > Backup & Restore* : sauvegarde automatique de `config.xml` (package **AutoConfigBackup** ou export planifié) ; la VM est aussi sauvegardée par PBS.
- Journalisation des règles de refus envoyée à Zabbix (syslog distant) pour repérer les flux anormaux.
