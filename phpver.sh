#!/bin/bash

# Config

PWD=$(pwd)
TXT_ERROR="[\e[0;31mERROR\e[0;0m]"
TXT_OK="[\e[0;32mOK\e[0;0m]"
TXT_INFO="[\e[0;33mINFO\e[0;0m]"

# Demande de la version de PHP
echo -e $TXT_INFO "Sélectionnez la version de PHP en format suivant (Pour les versions 5.2 jusqu'à la 8.2 | EXEMPLE : 74 pour PHP 7.4) : "
read -r PHP_VERSION

# Check si la version est ok
if [[ ! $PHP_VERSION =~ ^(52|53|54|55|56|70|71|72|73|74|75|76|77|78|79|80|81|82|83)$ ]]; then
    echo -e "$TXT_ERROR La version de PHP saisie '$PHP_VERSION' n'est pas correct. Veuillez entrer une version entre 52 et 83."
    exit 1
fi

# Rename old htaccess for bkp
HTACCESS_FILE=".htaccess"
NEW_HTACCESS_FILE="${HTACCESS_FILE}_"
COUNTER=1

while [[ -f "$NEW_HTACCESS_FILE" ]]; do
    NEW_HTACCESS_FILE="${HTACCESS_FILE}_$COUNTER"
    COUNTER=$((COUNTER + 1))
done

if [[ -f "$HTACCESS_FILE" ]]; then
    mv "$HTACCESS_FILE" "$NEW_HTACCESS_FILE"
    echo -e "$TXT_OK Ancien fichier rename en $NEW_HTACCESS_FILE."
else
    echo -e "$TXT_OK Aucun fichier $HTACCESS_FILE à renommer."
fi

# Créer le nouveau .htaccess
BLOCK_TEMPLATE=$(cat <<EOL
<FilesMatch \\.php$>
SetHandler application/x-httpd-php$PHP_VERSION
</FilesMatch>
AddHandler application/x-httpd-php$PHP_VERSION .php
suPHP_ConfigPath $PWD/php.ini
EOL
)

# Créer le htaccess avec les règles
echo "$BLOCK_TEMPLATE" > "$HTACCESS_FILE"
echo -e "$TXT_OK Nouveau fichier $HTACCESS_FILE créé."

# Créer php.ini
PHP_INI_FILE="php.ini"

# Création du fichier php.ini avec les infos natives.
cat <<EOL > "$PHP_INI_FILE"
date.timezone=Europe/Paris
extension=mysqlnd.so
extension=nd_mysqli.so
extension=nd_pdo_mysql.so
extension=json.so
extension=intl.so
extension=mcrypt.so
extension=gd.so
extension=xml.so
extension=xmlreader.so
extension=xmlrpc.so
extension=xmlwriter.so
extension=soap.so
extension=tidy.so
extension=bcmath.so
extension=dom.so
extension=fileinfo.so
extension=imap.so
extension=zip.so
extension=mcrypt.so
extension=intl.so
extension=pdo.so
extension=fileinfo.so
extension=mbstring.so
extension=imagick.so
display_errors=off
memory_limit=2038M
max_input_vars=250000
max_execution_time=360
output_buffering=4096
upload_max_filesize=512M
post_max_size=512M
EOL

echo -e "$TXT_OK Le $PHP_INI_FILE est bien créé avec les options."

# Fin
echo -e "\n$TXT_OK Script terminé avec succès !"

rm -rf phpver.sh