#!/usr/bin/env bash
# Installation de GLPI 10 sur Debian 12 (Apache, PHP 8.2, MariaDB), arborescence conforme aux
# recommandations de sécurité GLPI : seul /public est exposé, config/données/journaux hors du web.
#   GLPI_DB_PASSWORD='…' ./install-glpi.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "À lancer en root" >&2; exit 1; }

GLPI_VERSION="${GLPI_VERSION:-10.0.17}"
GLPI_FQDN="${GLPI_FQDN:-glpi.ad.pmelab.fr}"
DB_NAME=glpi
DB_USER=glpi
: "${GLPI_DB_PASSWORD:?Définir GLPI_DB_PASSWORD}"

apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q apache2 mariadb-server libapache2-mod-php \
  php php-{curl,gd,intl,mysql,zip,bz2,mbstring,xml,ldap,apcu,bcmath,opcache} wget openssl

# --- Base de données ---
mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${GLPI_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
GRANT SELECT ON mysql.time_zone_name TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
# Fuseaux horaires dans MariaDB (GLPI les utilise)
mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null | mysql mysql

# --- Fichiers ---
if [[ ! -d /var/www/glpi ]]; then
  wget -q "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz" -O /tmp/glpi.tgz
  tar -xzf /tmp/glpi.tgz -C /var/www/
fi
install -d -o www-data -g www-data /etc/glpi /var/lib/glpi /var/log/glpi
[[ -d /var/www/glpi/files && ! -e /var/lib/glpi/_cache ]] && cp -a /var/www/glpi/files/. /var/lib/glpi/

cat > /var/www/glpi/inc/downstream.php <<'PHP'
<?php
define('GLPI_CONFIG_DIR', '/etc/glpi/');
if (file_exists(GLPI_CONFIG_DIR . '/local_define.php')) {
    require_once GLPI_CONFIG_DIR . '/local_define.php';
}
PHP
cat > /etc/glpi/local_define.php <<'PHP'
<?php
define('GLPI_VAR_DIR', '/var/lib/glpi');
define('GLPI_LOG_DIR', '/var/log/glpi');
PHP
chown -R www-data:www-data /var/www/glpi /etc/glpi /var/lib/glpi /var/log/glpi

# --- PHP : cookies de session sécurisés ---
PHPINI=$(ls /etc/php/*/apache2/php.ini | head -1)
sed -i 's/^;\?session.cookie_httponly.*/session.cookie_httponly = On/' "$PHPINI"
sed -i 's/^;\?session.cookie_secure.*/session.cookie_secure = On/' "$PHPINI"
sed -i 's/^;\?session.cookie_samesite.*/session.cookie_samesite = Lax/' "$PHPINI"

# --- Apache : HTTPS (certificat auto-signé du labo), HTTP redirigé ---
if [[ ! -f /etc/ssl/private/glpi.key ]]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 825 -subj "/CN=${GLPI_FQDN}" \
    -addext "subjectAltName=DNS:${GLPI_FQDN}" -keyout /etc/ssl/private/glpi.key -out /etc/ssl/certs/glpi.crt
fi
cat > /etc/apache2/sites-available/glpi.conf <<CONF
<VirtualHost *:80>
    ServerName ${GLPI_FQDN}
    Redirect permanent / https://${GLPI_FQDN}/
</VirtualHost>
<VirtualHost *:443>
    ServerName ${GLPI_FQDN}
    DocumentRoot /var/www/glpi/public
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/glpi.crt
    SSLCertificateKeyFile /etc/ssl/private/glpi.key
    <Directory /var/www/glpi/public>
        Require all granted
        RewriteEngine On
        RewriteCond %{HTTP:Authorization} ^(.+)$
        RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^(.*)$ index.php [QSA,L]
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/glpi-error.log
    CustomLog \${APACHE_LOG_DIR}/glpi-access.log combined
</VirtualHost>
CONF
a2enmod -q rewrite ssl
a2dissite -q 000-default
a2ensite -q glpi
systemctl reload apache2

# --- Installation de la base en ligne de commande ---
cd /var/www/glpi
if ! sudo -u www-data php bin/console glpi:system:status >/dev/null 2>&1; then
  sudo -u www-data php bin/console db:install --db-host=localhost --db-name="$DB_NAME" --db-user="$DB_USER" \
    --db-password="$GLPI_DB_PASSWORD" --default-language=fr_FR --no-interaction --reconfigure
fi
rm -f /var/www/glpi/install/install.php   # supprime l'assistant d'installation

# Tâches automatiques de GLPI (notifications, inventaire, nettoyage)
echo '* * * * * www-data /usr/bin/php /var/www/glpi/front/cron.php >/dev/null 2>&1' >/etc/cron.d/glpi

echo
echo "GLPI ${GLPI_VERSION} installé : https://${GLPI_FQDN}"
echo "Comptes par défaut à changer IMMÉDIATEMENT : glpi, tech, normal, post-only (mot de passe = identifiant)."
echo "Puis : Configuration > Authentification > Annuaires LDAP (voir docs/04-glpi.md)."
