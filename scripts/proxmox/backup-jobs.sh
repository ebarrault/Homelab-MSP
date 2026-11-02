#!/usr/bin/env bash
# Déclare le datastore PBS dans Proxmox VE et planifie les sauvegardes (à lancer sur l'hôte PVE).
#   PBS_PASSWORD=... PBS_FINGERPRINT=... ./backup-jobs.sh
set -euo pipefail

PBS_SERVER="${PBS_SERVER:-10.0.10.30}"
PBS_DATASTORE="${PBS_DATASTORE:-labo}"
PBS_USER="${PBS_USER:-backup@pbs}"
: "${PBS_PASSWORD:?Variable PBS_PASSWORD requise}"
: "${PBS_FINGERPRINT:?Empreinte du certificat PBS requise (tableau de bord PBS > Show Fingerprint)}"

if ! pvesm status | grep -q '^pbs-labo'; then
  pvesm add pbs pbs-labo --server "$PBS_SERVER" --datastore "$PBS_DATASTORE" \
    --username "$PBS_USER" --password "$PBS_PASSWORD" --fingerprint "$PBS_FINGERPRINT" \
    --content backup
fi

# Serveurs : toutes les nuits à 1 h, mode snapshot (sans arrêt), rétention 7 j / 4 sem / 6 mois
pvesh create /cluster/backup --id serveurs-nuit --schedule '01:00' --storage pbs-labo \
  --vmid 100,110,120,121 --mode snapshot --enabled 1 \
  --prune-backups 'keep-daily=7,keep-weekly=4,keep-monthly=6' \
  --notes-template '{{guestname}} — sauvegarde nocturne' \
  --mailnotification failure --mailto admin@pmelab.fr

# Postes : une fois par semaine (dimanche 3 h)
pvesh create /cluster/backup --id postes-hebdo --schedule 'sun 03:00' --storage pbs-labo \
  --vmid 200,201 --mode snapshot --enabled 1 \
  --prune-backups 'keep-weekly=4' --mailnotification failure --mailto admin@pmelab.fr

pvesh get /cluster/backup --output-format text
