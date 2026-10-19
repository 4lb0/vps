#!/bin/bash
# shellcheck shell=bash
#
# Configuracion y helpers compartidos por los scripts de Nube.
# Este archivo se carga con "source"; no se ejecuta solo.
#
# Orden de precedencia:
#   1. Variables de entorno (NUBE_*)
#   2. /etc/nube/nube.conf
#   3. Valores por defecto (pensados para una instalacion nueva)
#
# Nube administra UN solo usuario de deploy (NUBE_USER) y UN dominio base.
# Todo lo que no este definido aca se toma de nube.conf.example.

NUBE_CONFIG="${NUBE_CONFIG:-/etc/nube/nube.conf}"

if [ -r "$NUBE_CONFIG" ]; then
    # shellcheck disable=SC1090
    . "$NUBE_CONFIG"
fi

# --- Identidad ---------------------------------------------------------------

# Unico usuario de deploy: dueno de los repositorios y de los sitios.
NUBE_USER="${NUBE_USER:-nube}"
# Email de contacto del usuario. Se usa para la clave GPG de deploy.
NUBE_USER_MAIL="${NUBE_USER_MAIL:-}"

# --- Dominio y web -----------------------------------------------------------

# Dominio base de los subdominios automaticos (app.$NUBE_BASE_DOMAIN).
# Cambialo en /etc/nube/nube.conf: el valor de abajo es solo un ejemplo.
NUBE_BASE_DOMAIN="${NUBE_BASE_DOMAIN:-nube.example.com}"
NUBE_WEB_ROOT="${NUBE_WEB_ROOT:-/var/www}"
NUBE_WEB_GROUP="${NUBE_WEB_GROUP:-www-data}"
NUBE_SSH_GROUP="${NUBE_SSH_GROUP:-nube}"
NUBE_PHP_VERSION="${NUBE_PHP_VERSION:-8.3}"

# --- Certificados ------------------------------------------------------------

NUBE_ACME_HOME="${NUBE_ACME_HOME:-$HOME/.acme.sh}"
NUBE_ACME_MODE="${NUBE_ACME_MODE:-webroot}"
NUBE_ACME_WEBROOT="${NUBE_ACME_WEBROOT:-$NUBE_WEB_ROOT/acme}"
NUBE_NGINX_SSL_DIR="${NUBE_NGINX_SSL_DIR:-/etc/nginx/ssl}"
NUBE_NGINX_DIR="${NUBE_NGINX_DIR:-/etc/nginx}"
NUBE_FAIL2BAN_DIR="${NUBE_FAIL2BAN_DIR:-/etc/fail2ban}"

# --- MySQL -------------------------------------------------------------------

NUBE_MYSQL_HOST="${NUBE_MYSQL_HOST:-127.0.0.1}"
NUBE_MYSQL_PORT="${NUBE_MYSQL_PORT:-3306}"

# --- Archivos del usuario de deploy ------------------------------------------

NUBE_SECRETS_FILE="${NUBE_SECRETS_FILE:-$HOME/secrets.gpg}"
NUBE_DEPLOY_LOG="${NUBE_DEPLOY_LOG:-$HOME/nube-deploy.log}"

# --- Instalacion -------------------------------------------------------------

NUBE_GIT_SHELL="${NUBE_GIT_SHELL:-$(command -v git-shell 2>/dev/null || true)}"
NUBE_HOOK_BIN="${NUBE_HOOK_BIN:-/usr/local/bin/nube-hook-post-update}"
NUBE_APPLY_BIN="${NUBE_APPLY_BIN:-/usr/local/bin/nube-apply-config}"
NUBE_NO_INTERACTIVE_LOGIN="${NUBE_NO_INTERACTIVE_LOGIN:-/usr/local/lib/nube/no-interactive-login.sh}"

# --- Repositorio del servidor (configuracion por git push) -------------------
#
# Ademas de los repositorios de cada app, el servidor tiene uno propio:
# este repositorio. Un push a $NUBE_SERVER_REPO aplica la configuracion
# (scripts en /usr/local, nginx en /etc/nginx, fail2ban en /etc/fail2ban).

NUBE_SERVER_REPO="${NUBE_SERVER_REPO:-/home/$NUBE_USER/git/nube.git}"
NUBE_SERVER_SRC="${NUBE_SERVER_SRC:-/srv/nube}"
NUBE_SERVER_REF="${NUBE_SERVER_REF:-main}"

export NUBE_USER NUBE_USER_MAIL NUBE_BASE_DOMAIN NUBE_WEB_ROOT NUBE_WEB_GROUP
export NUBE_SSH_GROUP NUBE_PHP_VERSION NUBE_ACME_HOME NUBE_ACME_MODE
export NUBE_ACME_WEBROOT NUBE_NGINX_SSL_DIR NUBE_NGINX_DIR NUBE_FAIL2BAN_DIR
export NUBE_MYSQL_HOST NUBE_MYSQL_PORT NUBE_SECRETS_FILE NUBE_DEPLOY_LOG
export NUBE_HOOK_BIN NUBE_APPLY_BIN NUBE_NO_INTERACTIVE_LOGIN NUBE_GIT_SHELL
export NUBE_SERVER_REPO NUBE_SERVER_SRC NUBE_SERVER_REF

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

nube_require_root() {
    [ "$(id -u)" -eq 0 ] || nube_die "ejecuta este script como root (sudo)"
}

# Home del usuario de deploy.
nube_home() {
    getent passwd "$NUBE_USER" | cut -d: -f6
}

nube_user_exists() {
    id "$NUBE_USER" >/dev/null 2>&1
}

# Convierte un dominio en un nombre seguro para base de datos / slug.
nube_slug() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9_]/_/g'
}

# Escapa un valor para usarlo como reemplazo en sed.
nube_sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
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

# Comprueba que NUBE_BASE_DOMAIN tenga un valor usable.
nube_require_base_domain() {
    [ -n "$NUBE_BASE_DOMAIN" ] || nube_die "define NUBE_BASE_DOMAIN en $NUBE_CONFIG"
    nube_valid_domain "$NUBE_BASE_DOMAIN" || nube_die "NUBE_BASE_DOMAIN invalido: $NUBE_BASE_DOMAIN"
}

nube_url() {
    printf 'https://%s' "$1"
}

# Escribe en $2 el contenido de $1 reemplazando los placeholders #NUBE_*#.
nube_render_template() {
    local src="$1" dst="$2"

    sed \
        -e "s|#NUBE_USER#|$(nube_sed_escape "$NUBE_USER")|g" \
        -e "s|#NUBE_BASE_DOMAIN#|$(nube_sed_escape "$NUBE_BASE_DOMAIN")|g" \
        -e "s|#NUBE_BASE_DOMAIN_REGEX#|$(nube_sed_escape "$(printf '%s' "$NUBE_BASE_DOMAIN" | sed 's/\./\\./g')")|g" \
        -e "s|#NUBE_WEB_ROOT#|$(nube_sed_escape "$NUBE_WEB_ROOT")|g" \
        -e "s|#NUBE_WEB_GROUP#|$(nube_sed_escape "$NUBE_WEB_GROUP")|g" \
        -e "s|#NUBE_PHP_VERSION#|$(nube_sed_escape "$NUBE_PHP_VERSION")|g" \
        -e "s|#NUBE_NGINX_SSL_DIR#|$(nube_sed_escape "$NUBE_NGINX_SSL_DIR")|g" \
        -e "s|#NUBE_ACME_WEBROOT#|$(nube_sed_escape "$NUBE_ACME_WEBROOT")|g" \
        "$src" > "$dst"
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

    # El contenido es generado por init-user.sh con printf %q.
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

# Escribe o reemplaza VAR="valor" en un archivo de configuracion.
nube_conf_set() {
    local var="$1" value="$2" file="${3:-$NUBE_CONFIG}"

    if grep -qE "^${var}=" "$file" 2>/dev/null; then
        sed -i -E "s|^${var}=.*|${var}=\"$(nube_sed_escape "$value")\"|" "$file"
    else
        printf '%s="%s"\n' "$var" "$value" >> "$file"
    fi
}

# Genera un certificado autofirmado para *.NUBE_BASE_DOMAIN si aun no hay
# ninguno: permite que nginx arranque antes de emitir el certificado real
# (acme.sh lo sobreescribe al hacer --install-cert).
nube_ensure_ssl_placeholder() {
    local crt="$NUBE_NGINX_SSL_DIR/nube.crt"
    local key="$NUBE_NGINX_SSL_DIR/nube.key"

    [ -f "$crt" ] && [ -f "$key" ] && return 0

    if ! command -v openssl >/dev/null 2>&1; then
        nube_warn "openssl no esta instalado: no puedo crear un certificado de relleno"
        return 0
    fi

    install -d -o root -g "$NUBE_WEB_GROUP" -m 2770 "$NUBE_NGINX_SSL_DIR"
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -batch \
        -subj "/CN=$NUBE_BASE_DOMAIN" \
        -keyout "$key" -out "$crt" 2>/dev/null || {
        nube_warn "no se pudo generar el certificado de relleno en $NUBE_NGINX_SSL_DIR"
        return 0
    }
    chmod 0640 "$crt" "$key" 2>/dev/null || true
    nube_info "certificado de relleno creado en $NUBE_NGINX_SSL_DIR (reemplazalo con el wildcard)"
}

# Aplica la configuracion de nginx del directorio $1/nginx.
# Deja un backup y lo restaura si "nginx -t" falla.
nube_apply_nginx_config() {
    local source="$1/nginx"
    local -a targets=(
        nginx.conf
        conf.d/nube.conf
        snippets/nube-acme.conf
        snippets/nube-ssl.conf
        snippets/nube-php-fpm.conf
        snippets/nube-security-headers.conf
        snippets/nube-block-scanners.conf
    )

    if [ ! -d "$source" ]; then
        nube_warn "no hay $source: no aplico configuracion de nginx"
        return 0
    fi

    if ! command -v nginx >/dev/null 2>&1; then
        nube_warn "nginx no esta instalado: instala nginx y volve a aplicar la configuracion"
        return 0
    fi

    local stamp backup restore_failed=0
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    backup="$NUBE_NGINX_DIR/.nube-backup-$stamp"

    nube_info "aplicando configuracion de nginx desde $source"

    local rel
    for rel in "${targets[@]}"; do
        if [ -e "$NUBE_NGINX_DIR/$rel" ] || [ -L "$NUBE_NGINX_DIR/$rel" ]; then
            mkdir -p "$backup/$(dirname "$rel")"
            cp -a "$NUBE_NGINX_DIR/$rel" "$backup/$rel" 2>/dev/null || true
        fi
    done

    install -d -m 0755 "$NUBE_NGINX_DIR/conf.d" "$NUBE_NGINX_DIR/snippets"

    nube_render_template "$source/nginx.conf"        "$NUBE_NGINX_DIR/nginx.conf"
    nube_render_template "$source/conf.d/nube.conf"  "$NUBE_NGINX_DIR/conf.d/nube.conf"
    local snippet
    for snippet in "$source"/snippets/*.conf; do
        [ -e "$snippet" ] || continue
        nube_render_template "$snippet" "$NUBE_NGINX_DIR/snippets/$(basename "$snippet")"
    done
    chmod 0644 "$NUBE_NGINX_DIR/nginx.conf" "$NUBE_NGINX_DIR/conf.d/nube.conf" \
        "$NUBE_NGINX_DIR"/snippets/*.conf 2>/dev/null || true

    local output
    if output="$(nginx -t 2>&1)"; then
        nube_info "nginx -t ok"
        systemctl reload nginx 2>/dev/null || systemctl start nginx 2>/dev/null || \
            nube_warn "no se pudo recargar nginx: revisalo a mano"
        rm -rf "$backup"
        return 0
    fi

    printf '%s\n' "$output" >&2
    nube_warn "nginx -t fallo: restauro la configuracion anterior"
    for rel in "${targets[@]}"; do
        if [ -e "$backup/$rel" ] || [ -L "$backup/$rel" ]; then
            install -d "$(dirname "$NUBE_NGINX_DIR/$rel")"
            cp -a "$backup/$rel" "$NUBE_NGINX_DIR/$rel" 2>/dev/null || restore_failed=1
        else
            rm -f "$NUBE_NGINX_DIR/$rel" 2>/dev/null || true
        fi
    done

    [ "$restore_failed" -eq 0 ] || nube_warn "no pude restaurar todo: el backup esta en $backup"
    nube_die "la configuracion de nginx no se aplico. Corregila en nginx/ y volve a hacer push"
}

# Aplica la configuracion de fail2ban del directorio $1/fail2ban.
nube_apply_fail2ban_config() {
    local source="$1/fail2ban"

    [ -d "$source" ] || return 0

    if [ ! -d "$NUBE_FAIL2BAN_DIR" ]; then
        nube_warn "fail2ban no esta instalado (sudo apt install -y fail2ban); no aplico $source"
        return 0
    fi

    nube_info "aplicando configuracion de fail2ban"
    install -d -m 0755 "$NUBE_FAIL2BAN_DIR/filter.d"

    local filter
    for filter in "$source"/filter.d/*.conf; do
        [ -e "$filter" ] || continue
        install -m 0644 "$filter" "$NUBE_FAIL2BAN_DIR/filter.d/$(basename "$filter")"
    done

    # jail.local se crea una sola vez: puede tener ajustes locales (ignoreip).
    if [ -f "$source/jail.local" ] && [ ! -f "$NUBE_FAIL2BAN_DIR/jail.local" ]; then
        install -m 0644 "$source/jail.local" "$NUBE_FAIL2BAN_DIR/jail.local"
        nube_info "creado $NUBE_FAIL2BAN_DIR/jail.local"
    fi

    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        systemctl restart fail2ban 2>/dev/null || nube_warn "no se pudo reiniciar fail2ban"
    fi
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
