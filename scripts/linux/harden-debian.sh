#!/usr/bin/env bash
# Durcissement de base d'un serveur Debian 12 du labo.
#   ./harden-debian.sh 80,443          ports ouverts en plus de SSH (ex. GLPI)
#   ./harden-debian.sh 80,443,10051    (Zabbix : interface + agents actifs)
# Prérequis : votre clé publique SSH déjà copiée (ssh-copy-id), sinon vous perdez l'accès.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "À lancer en root" >&2; exit 1; }

EXTRA_PORTS="${1:-}"
ADMIN_NETS=("10.0.10.0/24" "10.0.99.0/24")   # serveurs + VPN d'administration
NTP_SERVER="${NTP_SERVER:-10.0.10.10}"      # le contrôleur de domaine

if ! compgen -G "/root/.ssh/authorized_keys" >/dev/null && ! compgen -G "/home/*/.ssh/authorized_keys" >/dev/null; then
  echo "Aucune clé SSH autorisée trouvée : abandon pour ne pas se bloquer dehors." >&2
  exit 1
fi

apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q ufw fail2ban unattended-upgrades chrony qemu-guest-agent

# SSH : clés uniquement, pas de root
install -d /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-durcissement.conf <<'CONF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding no
CONF
sshd -t && systemctl reload ssh

# Pare-feu local : tout refuser en entrée sauf SSH depuis les réseaux d'administration
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
for net in "${ADMIN_NETS[@]}"; do ufw allow from "$net" to any port 22 proto tcp; done
ufw allow from 10.0.10.21 to any port 10050 proto tcp comment 'agent Zabbix'
if [[ -n "$EXTRA_PORTS" ]]; then
  IFS=',' read -ra ports <<<"$EXTRA_PORTS"
  for p in "${ports[@]}"; do ufw allow "$p/tcp"; done
fi
ufw --force enable

# Fail2ban sur SSH
cat > /etc/fail2ban/jail.d/sshd.local <<'CONF'
[sshd]
enabled = true
maxretry = 4
findtime = 10m
bantime = 1h
CONF
systemctl restart fail2ban

# Mises à jour de sécurité automatiques
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF

# Heure synchronisée sur le DC (indispensable pour Kerberos/LDAP et des journaux cohérents)
sed -i 's/^pool .*/# &/' /etc/chrony/chrony.conf
grep -q "^server $NTP_SERVER" /etc/chrony/chrony.conf || echo "server $NTP_SERVER iburst" >>/etc/chrony/chrony.conf
systemctl restart chrony
timedatectl set-timezone Europe/Paris

systemctl enable --now qemu-guest-agent
echo "Durcissement terminé."
ufw status verbose
