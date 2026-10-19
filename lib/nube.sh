#!/bin/bash
# shellcheck shell=bash
#
# Configuracion y helpers compartidos por los scripts de Nube.
# Este archivo se carga con "source"; no se ejecuta solo.
#
# Orden de precedencia:
#   1. Variables de entorno (NUBE_*)
#   2. /etc/nube/nube.conf
#   3. Valores por defecto (compatibles con el servidor original)
#
# Los valores por defecto conservan el comportamiento historico de
# nube.pragmore.com. En una instalacion nueva conviene definir todo en
# /etc/nube/nube.conf (ver nube.conf.example).

NUBE_CONFIG="${NUBE_CONFIG:-/etc/nube/nube.conf}"

if [ -r "$NUBE_CONFIG" ]; then
    # shellcheck disable=SC1090
    . "$NUBE_CONFIG"
fi

NUBE_BASE_DOMAIN="${NUBE_BASE_DOMAIN:-nube.pragmore.com}"
NUBE_WEB_ROOT="${NUBE_WEB_ROOT:-/var/www}"
NUBE_WEB_GROUP="${NUBE_WEB_GROUP:-www-data}"
NUBE_SSH_GROUP="${NUBE_SSH_GROUP:-nube}"
NUBE_PHP_VERSION="${NUBE_PHP_VERSION:-8.3}"
NUBE_ACME_HOME="${NUBE_ACME_HOME:-$HOME/.acme.sh}"
NUBE_ACME_MODE="${NUBE_ACME_MODE:-webroot}"
NUBE_ACME_WEBROOT="${NUBE_ACME_WEBROOT:-$NUBE_WEB_ROOT/acme}"
NUBE_NGINX_SSL_DIR="${NUBE_NGINX_SSL_DIR:-/etc/nginx/ssl}"
NUBE_MYSQL_HOST="${NUBE_MYSQL_HOST:-127.0.0.1}"
NUBE_MYSQL_PORT="${NUBE_MYSQL_PORT:-3306}"
NUBE_SECRETS_FILE="${NUBE_SECRETS_FILE:-$HOME/secrets.gpg}"
NUBE_DEPLOY_LOG="${NUBE_DEPLOY_LOG:-$HOME/nube-deploy.log}"
NUBE_HOOK_BIN="${NUBE_HOOK_BIN:-/usr/local/bin/nube-hook-post-update}"
NUBE_NO_INTERACTIVE_LOGIN="${NUBE_NO_INTERACTIVE_LOGIN:-/usr/local/lib/nube/no-interactive-login.sh}"
NUBE_GIT_SHELL="${NUBE_GIT_SHELL:-$(command -v git-shell 2>/dev/null || true)}"

export NUBE_BASE_DOMAIN NUBE_WEB_ROOT NUBE_WEB_GROUP NUBE_SSH_GROUP NUBE_PHP_VERSION
export NUBE_ACME_HOME NUBE_ACME_MODE NUBE_ACME_WEBROOT NUBE_NGINX_SSL_DIR
export NUBE_MYSQL_HOST NUBE_MYSQL_PORT NUBE_SECRETS_FILE NUBE_DEPLOY_LOG
export NUBE_HOOK_BIN NUBE_NO_INTERACTIVE_LOGIN NUBE_GIT_SHELL

# --- Helpers -----------------------------------------------------------------

nube_info() {
    printf 'nube: %s\n' "$*" >&2
}

nube_warn() {
    printf 'nube: aviso: %s\n' "$*" >&2
}

nube_die() {
    printf 'nube: error: %s\n' "$*" >&2
    exit 1
}

# Convierte un dominio en un nombre seguro para base de datos / slug.
nube_slug() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9_]/_/g'
}

# Valida un dominio o subdominio simple (sin esquema, sin puerto).
nube_valid_domain() {
    printf '%s' "$1" | grep -Eq '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
}

# Valida un nombre de repositorio/aplicacion.
nube_valid_name() {
    printf '%s' "$1" | grep -Eq '^[a-z][a-z0-9_-]{0,31}$'
}

# Valida un email basico (no reemplaza una validacion real de entrega).
nube_valid_email() {
    printf '%s' "$1" | grep -Eq '^[^@[:space:]]+@([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
}

nube_url() {
    printf 'https://%s' "$1"
}

# Descifra ~/secrets.gpg y exporta NUBE_DB_USER / NUBE_DB_PASS.
# No falla si el archivo no existe: algunos comandos no necesitan DB.
nube_load_secrets() {
    local content

    NUBE_DB_USER="${NUBE_DB_USER:-}"
    NUBE_DB_PASS="${NUBE_DB_PASS:-}"
    export NUBE_DB_USER NUBE_DB_PASS

    [ -f "$NUBE_SECRETS_FILE" ] || return 0

    if ! content="$(gpg --quiet --batch --decrypt "$NUBE_SECRETS_FILE" 2>/dev/null)"; then
        nube_die "no se pudo descifrar $NUBE_SECRETS_FILE (¿existe la clave GPG del usuario?)"
    fi

    # El contenido es generado por add-user.sh con printf %q.
    eval "$content"
    export NUBE_DB_USER NUBE_DB_PASS
}

# Crea ~/www/<dominio>/public y el symlink en /var/www/<dominio>.
# Imprime la ruta web (sin salto de linea) para poder usarla en $().
nube_ensure_web_dir() {
    local domain="$1"
    local web_path="$HOME/www/$domain"
    local public_path="$web_path/public"
    local link_path="$NUBE_WEB_ROOT/$domain"

    mkdir -p "$public_path"

    if [ -n "$NUBE_WEB_GROUP" ] && getent group "$NUBE_WEB_GROUP" >/dev/null 2>&1; then
        chgrp -R "$NUBE_WEB_GROUP" "$public_path" 2>/dev/null || \
            nube_warn "no se pudo cambiar el grupo de $public_path"
        chmod 2775 "$public_path" 2>/dev/null || true
    fi

    if [ ! -e "$link_path" ] && [ ! -L "$link_path" ]; then
        if ! ln -s "$web_path" "$link_path" 2>/dev/null; then
            nube_die "no se pudo crear $link_path. Verifica que $NUBE_WEB_ROOT sea escribible por el grupo $NUBE_WEB_GROUP (ver docs/03-instalar-nube.md)"
        fi
    fi

    printf '%s' "$public_path"
}

# Recarga nginx si el usuario actual puede hacerlo. Si no, avisa y sigue.
nube_reload_nginx() {
    if [ "$(id -u)" -eq 0 ]; then
        nginx -t && systemctl reload nginx
    elif sudo -n true 2>/dev/null && sudo -n nginx -t 2>/dev/null; then
        sudo -n systemctl reload nginx
    else
        nube_info "recuerda recargar nginx: sudo nginx -t && sudo systemctl reload nginx"
        return 0
    fi
}
