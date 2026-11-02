#!/usr/bin/env bash
# Installation de Zabbix 7.0 LTS (serveur, interface web, agent 2) sur Debian 12 avec MariaDB.
#   ZBX_DB_PASSWORD='…' ./install-zabbix.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "À lancer en root" >&2; exit 1; }

: "${ZBX_DB_PASSWORD:?Définir ZBX_DB_PASSWORD}"
RELEASE_DEB="${RELEASE_DEB:-https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian12_all.deb}"

if ! dpkg -s zabbix-release >/dev/null 2>&1; then
  wget -q "$RELEASE_DEB" -O /tmp/zabbix-release.deb
  dpkg -i /tmp/zabbix-release.deb
fi
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q mariadb-server zabbix-server-mysql zabbix-frontend-php \
  zabbix-apache-conf zabbix-sql-scripts zabbix-agent2 locales jq curl

# Interface en français
sed -i 's/^# fr_FR.UTF-8/fr_FR.UTF-8/' /etc/locale.gen && locale-gen >/dev/null

# --- Base de données ---
mysql <<SQL
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${ZBX_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SQL
if [[ "$(mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix'")" -eq 0 ]]; then
  mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;"
  zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p"${ZBX_DB_PASSWORD}" zabbix
  mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;"
fi

# --- Configuration ---
sed -i "s/^# DBPassword=.*/DBPassword=${ZBX_DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
cat > /etc/zabbix/web/zabbix.conf.php <<PHP
<?php
\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = '${ZBX_DB_PASSWORD}';
\$DB['SCHEMA']   = '';
\$DB['ENCRYPTION'] = false;
\$ZBX_SERVER_NAME = 'Supervision labo';
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
PHP
chown www-data:www-data /etc/zabbix/web/zabbix.conf.php
chmod 640 /etc/zabbix/web/zabbix.conf.php

systemctl restart zabbix-server zabbix-agent2 apache2
systemctl enable -q zabbix-server zabbix-agent2 apache2

echo
echo "Zabbix installé : http://$(hostname -I | awk '{print $1}')/zabbix — compte Admin / zabbix (à changer)."
echo "Ensuite : ZBX_PASSWORD=… ./zabbix-autoregistration.sh pour l'enregistrement automatique des postes."
