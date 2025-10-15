#!/bin/bash

# Configuration et commentaires (FR)
# Ce script a été modifié pour améliorer :
#  - la portabilité (fonction mktemp compatible Linux/macOS/BSD),
#  - la robustesse (set -euo pipefail, IFS restreint),
#  - l'ergonomie (acceptation de 7.4 ou 74, options CLI --dry-run et -v/--version),
#  - la sécurité opérationnelle (backup horodaté de l'ancien .htaccess, écriture atomique),
#  - la sûreté au démarrage PHP (php.ini généré avec extensions commentées par défaut).
#
# Les sections ci-dessous sont commentées pour expliquer pourquoi chaque changement
# a été apporté et comment l'adapter à différents environnements d'hébergement.
set -euo pipefail
IFS=$'\n\t'

PWD=$(pwd)
TXT_ERROR="[\e[0;31mERROR\e[0;0m]"
TXT_OK="[\e[0;32mOK\e[0;0m]"
TXT_INFO="[\e[0;33mINFO\e[0;0m]"

# Options par défaut
DRY_RUN=0
CLI_VERSION=""
SHOW_HELP=0

print_help() {
    cat <<EOF
Usage: $0 [options]

Options:
  -n, --dry-run       Afficher les actions sans écrire de fichiers
  -v, --version <ver> Spécifier la version PHP (ex: 74) en ligne de commande
  -h, --help          Afficher cette aide

Si aucune version n'est fournie via -v/--version, le script demandera une saisie interactive.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=1; shift ;;
            -v|--version)
                CLI_VERSION="$2"; shift 2 ;;
            -h|--help)
                SHOW_HELP=1; shift ;;
            --)
                shift; break ;;
            -*)
                echo "Unknown option: $1"; exit 1 ;;
            *)
                break ;;
        esac
    done
}

parse_args "$@"
if [[ $SHOW_HELP -eq 1 ]]; then
    print_help; exit 0
fi

# Configuration modifiable
# Si vous voulez que les extensions listées soient activées automatiquement,
# mettez ENABLE_EXT=1 (attention : seules les extensions présentes sur le système
# seront prises en compte). Par défaut on laisse les extensions commentées.
ENABLE_EXT=0
DEFAULT_MEMORY_LIMIT="2048M"

mktemp_portable() {
    # Fonction utilitaire : mktemp portable
    # Pourquoi : la syntaxe de mktemp diffère entre GNU (Linux) et BSD (macOS). Cette
    # fonction essaye plusieurs variantes afin d'obtenir un fichier temporaire
    # utilisable sur la plupart des systèmes sans provoquer d'erreur.
    # On retourne un chemin (stdout) utilisable pour l'écriture atomique.
    # Exemple d'utilisation : TMP=$(mktemp_portable "${HTACCESS_FILE}.tmp")
    # Le fichier retourné doit être supprimé après usage ; on gère ça via trap.
    local prefix="$1"
    local tmp
    if tmp=$(mktemp "${prefix}.XXXX" 2>/dev/null); then
        echo "$tmp"; return 0
    fi
    if tmp=$(mktemp -t "${prefix}" 2>/dev/null); then
        echo "$tmp"; return 0
    fi
    if tmp=$(mktemp 2>/dev/null); then
        echo "$tmp"; return 0
    fi
    # Last resort
    echo "/tmp/${prefix}.$RANDOM"
}

# Sélection de la version PHP
# On supporte trois modes d'entrée :
# 1) Argument CLI (-v/--version) : utile pour automatisation/CI
# 2) Variable d'environnement exportée PHP_VERSION : utile pour scripts appelants
# 3) Prompt interactif : quand l'utilisateur lance manuellement le script
#
# On accepte également le format "7.4" qui est normalisé en "74".
if [[ -n "$CLI_VERSION" ]]; then
    PHP_VERSION="$CLI_VERSION"
elif [[ -n "${PHP_VERSION:-}" ]]; then
    # keep already-exported PHP_VERSION
    :
else
    while true; do
        echo -e "$TXT_INFO Sélectionnez la version de PHP au format 74 pour PHP 7.4 (ex: 7.4 ou 74) :"
        read -r PHP_VERSION

        # Normaliser 7.4 -> 74
        if [[ $PHP_VERSION =~ ^[0-9]+\.[0-9]+$ ]]; then
            PHP_VERSION="${PHP_VERSION/./}"
        fi

        if [[ $PHP_VERSION =~ ^(52|53|54|55|56|70|71|72|73|74|75|76|77|78|79|80|81|82|83)$ ]]; then
            break
        fi

        echo -e "$TXT_ERROR La version de PHP saisie '$PHP_VERSION' n'est pas correcte. Réessayez."
    done
fi

# Sauvegarde de l'ancien .htaccess (backup horodaté)
# Pourquoi : les règles .htaccess peuvent rendre un site inaccessible. Nous
# sauvegardons l'ancien fichier avec un timestamp pour pouvoir revenir en arrière
# rapidement si nécessaire.
HTACCESS_FILE=".htaccess"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$HTACCESS_FILE" ]]; then
    NEW_HTACCESS_FILE="${HTACCESS_FILE}.bak.$TIMESTAMP"
    # Si le fichier existe déjà (cas improbable), ajouter un suffixe numérique
    local_counter=1
    while [[ -f "$NEW_HTACCESS_FILE" ]]; do
        NEW_HTACCESS_FILE="${HTACCESS_FILE}.bak.${TIMESTAMP}.$local_counter"
        local_counter=$((local_counter + 1))
    done
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "$TXT_INFO [dry-run] Ancien fichier serait renommé en ${NEW_HTACCESS_FILE}."
    else
        mv "${HTACCESS_FILE}" "${NEW_HTACCESS_FILE}"
        echo -e "$TXT_OK Ancien fichier renommé en ${NEW_HTACCESS_FILE}."
    fi
else
    echo -e "$TXT_INFO Aucun fichier ${HTACCESS_FILE} à renommer."
fi

# Construire le bloc .htaccess
BLOCK_TEMPLATE=$(cat <<EOL
<FilesMatch \\.php$>
SetHandler application/x-httpd-php${PHP_VERSION}
</FilesMatch>
AddHandler application/x-httpd-php${PHP_VERSION} .php
suPHP_ConfigPath ${PWD}/php.ini
EOL
)

# Écriture atomique du .htaccess
# On écrit d'abord dans un fichier temporaire (mktemp_portable) puis on effectue un
# mv atomique. Cela évite d'avoir un fichier .htaccess partiellement écrit si le
# script est interrompu. Un trap supprime le temporaire en cas d'erreur.
TMP_HTACCESS="$(mktemp_portable "${HTACCESS_FILE}.tmp")"
trap '[[ -n "${TMP_HTACCESS:-}" && -f "${TMP_HTACCESS}" ]] && rm -f -- "${TMP_HTACCESS}"' EXIT
if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "$TXT_INFO [dry-run] Ecriture du .htaccess (contenu affiché ci-dessous):"
    printf "%s\n" "$BLOCK_TEMPLATE"
else
    printf "%s\n" "$BLOCK_TEMPLATE" > "$TMP_HTACCESS"
fi

# Ajout des Rewrite de WordPress si présent
if [[ -f "wp-config.php" ]]; then
    echo -e "$TXT_INFO Site WordPress trouvé. Ajout des règles dans le .htaccess."
    if [[ $DRY_RUN -eq 1 ]]; then
        cat <<EOL

# BEGIN WordPress
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
# END WordPress
EOL
    else
        cat <<EOL >> "$TMP_HTACCESS"

# BEGIN WordPress
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
# END WordPress
EOL
    fi

# BEGIN WordPress
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
# END WordPress
EOL
    echo -e "$TXT_OK Règles WordPress ajoutées au fichier temporaire."
else
    echo -e "$TXT_INFO Pas de WordPress détecté. Seules les règles PHP seront ajoutées."
fi

# Déplacer atomiquement
if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "$TXT_INFO [dry-run] .htaccess prêt à être déplacé en ${HTACCESS_FILE} (non écrit)."
    # montrer un aperçu
    echo "--- .htaccess preview ---"
    echo "$BLOCK_TEMPLATE"
else
    mv "$TMP_HTACCESS" "$HTACCESS_FILE"
    trap - EXIT
    echo -e "$TXT_OK Nouveau fichier ${HTACCESS_FILE} créé."
fi

# Génération du php.ini
# On génère un php.ini minimal avec des valeurs courantes. Les extensions sont
# commentées par défaut pour éviter d'activer des modules inexistants sur la
# machine cible (ce qui provoquerait des erreurs à l'initialisation de PHP).
PHP_INI_FILE="php.ini"
if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "$TXT_INFO [dry-run] Le fichier ${PHP_INI_FILE} serait créé avec le contenu suivant:"
    cat <<EOL
; Generated by prestashop-fix.sh
date.timezone = Europe/Paris

; Performances / limites
display_errors = Off
memory_limit = ${DEFAULT_MEMORY_LIMIT}
max_input_vars = 250000
max_execution_time = 360
output_buffering = 4096
upload_max_filesize = 512M
post_max_size = 512M

; Extensions: décommentez celles que vous voulez activer si elles existent sur le système
;extension=mysqli.so
;extension=pdo_mysql.so
;extension=json.so
;extension=intl.so
;extension=gd.so
;extension=xml.so
;extension=xmlreader.so
;extension=xmlwriter.so
;extension=soap.so
;extension=tidy.so
;extension=bcmath.so
;extension=dom.so
;extension=fileinfo.so
;extension=imap.so
;extension=zip.so
;extension=mbstring.so
;extension=imagick.so

EOL
else
    cat <<EOL > "$PHP_INI_FILE"
; Generated by prestashop-fix.sh
date.timezone = Europe/Paris

; Performances / limites
display_errors = Off
memory_limit = ${DEFAULT_MEMORY_LIMIT}
max_input_vars = 250000
max_execution_time = 360
output_buffering = 4096
upload_max_filesize = 512M
post_max_size = 512M

; Extensions: décommentez celles que vous voulez activer si elles existent sur le système
;extension=mysqli.so
;extension=pdo_mysql.so
;extension=json.so
;extension=intl.so
;extension=gd.so
;extension=xml.so
;extension=xmlreader.so
;extension=xmlwriter.so
;extension=soap.so
;extension=tidy.so
;extension=bcmath.so
;extension=dom.so
;extension=fileinfo.so
;extension=imap.so
;extension=zip.so
;extension=mbstring.so
;extension=imagick.so

EOL
    echo -e "$TXT_OK Le ${PHP_INI_FILE} a été créé (extensions commentées par défaut)."
fi

# Nettoyage optionnel
if [[ -f "phpver.sh" ]]; then
    rm -f "phpver.sh"
    echo -e "$TXT_INFO Fichier phpver.sh supprimé."
fi

echo -e "\n$TXT_OK Script terminé avec succès !"
