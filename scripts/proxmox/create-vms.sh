#!/usr/bin/env bash
# Crée les machines virtuelles du labo sur Proxmox VE 8 (à lancer en root sur l'hôte).
# Les ISO doivent être présentes dans le stockage "local" (Datacenter > local > ISO Images).
#
#   ./create-vms.sh            crée toutes les VM absentes
#   ./create-vms.sh --dry-run  affiche les commandes sans les exécuter
set -euo pipefail

STORAGE="${STORAGE:-local-lvm}"
ISO_STORE="${ISO_STORE:-local}"
ISO_PFSENSE="${ISO_PFSENSE:-netgate-installer-amd64.iso}"
ISO_WINSRV="${ISO_WINSRV:-SERVER_EVAL_x64FRE_fr-fr.iso}"
ISO_WIN11="${ISO_WIN11:-Win11_24H2_French_x64.iso}"
ISO_DEBIAN="${ISO_DEBIAN:-debian-12-amd64-netinst.iso}"
ISO_PBS="${ISO_PBS:-proxmox-backup-server_3.2-1.iso}"
ISO_VIRTIO="${ISO_VIRTIO:-virtio-win.iso}"   # pilotes VirtIO pour Windows

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

run() {
  echo "+ $*"
  if ! $DRY_RUN; then "$@"; fi
}

vm_exists() { qm status "$1" >/dev/null 2>&1; }

# create_vm ID NOM CPU RAM_MO DISQUE_GO ISO TYPE_OS VLAN [options supplémentaires…]
create_vm() {
  local id=$1 name=$2 cores=$3 mem=$4 disk=$5 iso=$6 ostype=$7 vlan=$8
  shift 8
  if vm_exists "$id"; then
    echo "= VM $id ($name) déjà présente, ignorée"
    return
  fi
  run qm create "$id" --name "$name" --cores "$cores" --memory "$mem" --cpu host \
    --ostype "$ostype" --scsihw virtio-scsi-single --agent enabled=1 \
    --scsi0 "${STORAGE}:${disk},discard=on,ssd=1" \
    --ide2 "${ISO_STORE}:iso/${iso},media=cdrom" --boot "order=scsi0;ide2" \
    --net0 "virtio,bridge=vmbr1,tag=${vlan}" --onboot 1 "$@"
}

# --- pfSense : deux cartes (WAN sur vmbr0, trunk VLAN sur vmbr1) ---
if ! vm_exists 100; then
  run qm create 100 --name pfsense --cores 2 --memory 2048 --cpu host --ostype other \
    --scsihw virtio-scsi-single --scsi0 "${STORAGE}:16" \
    --ide2 "${ISO_STORE}:iso/${ISO_PFSENSE},media=cdrom" --boot "order=scsi0;ide2" \
    --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbr1 \
    --onboot 1 --startup order=1,up=60
fi

# --- Serveurs (VLAN 10) ---
WIN_OPTS=(--bios ovmf --machine q35 --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=1"
          --tpmstate0 "${STORAGE}:1,version=v2.0" --ide0 "${ISO_STORE}:iso/${ISO_VIRTIO},media=cdrom")
create_vm 110 dc01   2 4096 60 "$ISO_WINSRV" win11 10 "${WIN_OPTS[@]}" --startup order=2,up=120
create_vm 120 glpi   2 2048 32 "$ISO_DEBIAN" l26   10 --startup order=3
create_vm 121 zabbix 2 4096 40 "$ISO_DEBIAN" l26   10 --startup order=3
create_vm 130 pbs    2 2048 32 "$ISO_PBS"    l26   10 --startup order=4 \
  --scsi1 "${STORAGE}:200,discard=on"   # disque dédié au datastore de sauvegarde

# --- Postes (VLAN 20) ---
create_vm 200 client01 2 4096 64 "$ISO_WIN11" win11 20 "${WIN_OPTS[@]}"
create_vm 201 client02 2 4096 64 "$ISO_WIN11" win11 20 "${WIN_OPTS[@]}"

echo
echo "Terminé. VM présentes :"
$DRY_RUN || qm list
