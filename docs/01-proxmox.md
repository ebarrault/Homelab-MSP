# 1. Proxmox VE

## Installation

1. Installer Proxmox VE 8 depuis la clé USB, adresse fixe **192.168.1.10/24**, passerelle 192.168.1.1.
2. Sans abonnement : désactiver le dépôt *enterprise* et activer *no-subscription* (*Mises à jour > Dépôts*), puis `apt update && apt full-upgrade`.
3. Activer l'authentification à deux facteurs (TOTP) sur `root@pam` (*Datacenter > Permissions > Two Factor*).
4. Créer un compte d'administration nominatif `erwan@pve` (rôle *Administrator*) et ne plus utiliser root au quotidien.

## Réseau

Le fichier [`scripts/proxmox/network-interfaces.example`](../scripts/proxmox/network-interfaces.example) décrit :

- **vmbr0** : pont sur la carte physique, réseau de la box → WAN de pfSense + interface d'administration de Proxmox ;
- **vmbr1** : pont **interne sans carte physique**, *VLAN aware* (VLAN 10 et 20). Les machines du labo ne sont joignables qu'à travers pfSense.

```bash
cp /etc/network/interfaces /etc/network/interfaces.bak
# adapter enp1s0 au nom réel de la carte (ip link), puis :
ifreload -a
```

## Création des VM

Télécharger les ISO dans *local > ISO Images* (pfSense, Windows Server 2022 évaluation, Windows 11, Debian 12 netinst, Proxmox Backup Server, pilotes VirtIO), puis :

```bash
./scripts/proxmox/create-vms.sh --dry-run   # vérifier
./scripts/proxmox/create-vms.sh
```

Points notables : disques VirtIO SCSI avec *discard* (TRIM), agent QEMU activé, UEFI + TPM 2.0 pour Windows 11/Server 2022, **ordre de démarrage** (pfSense → DC01 → services → PBS) pour que le DNS et l'AD soient prêts avant les autres.

> Windows : à l'installation, charger le pilote de disque depuis l'ISO VirtIO (`vioscsi\w11\amd64`), puis installer `virtio-win-guest-tools.exe` (réseau, ballooning, agent QEMU).
