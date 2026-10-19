#!/bin/bash
#
# Instala y aplica la configuracion de Nube en el sistema.
#
#   sudo ./install.sh [directorio-origen]
#
# Es idempotente: se puede volver a ejecutar despues de un git pull o de un
# push al repositorio del servidor. Hace lo siguiente:
#
#   1. copia los scripts a /usr/local/lib/nube y crea los comandos;
#   2. deja /etc/nube/nube.conf (solo si no existe);
#   3. aplica nginx/  -> /etc/nginx/   (con backup y rollback si nginx -t falla)
#   4. aplica fail2ban/ -> /etc/fail2ban/
#   5. recarga nginx y fail2ban
#
# Cuando lo invoca "nube-apply-config" (un push), el origen es la copia de
# trabajo del repositorio del servidor.

set -euo pipefail

NUBE_SRC="${1:-}"
if [ -z "$NUBE_SRC" ]; then
    NUBE_SELF="${BASH_SOURCE[0]}"
    if command -v readlink >/dev/null 2>&1; then
        NUBE_SELF="$(readlink -f "$NUBE_SELF" 2>/dev/null || printf '%s' "$NUBE_SELF")"
    fi
    NUBE_SRC="$(cd -- "$(dirname -- "$NUBE_SELF")" && pwd)"
fi

# shellcheck source=/dev/null
. "$NUBE_SRC/lib.sh"

nube_require_root

if [ ! -f "$NUBE_SRC/install.sh" ]; then
    nube_die "no encuentro install.sh en $NUBE_SRC (¿pasaste un directorio de origen valido?)"
fi

readonly NUBE_PREFIX="${NUBE_PREFIX:-/usr/local}"
readonly NUBE_LIBDIR="$NUBE_PREFIX/lib/nube"
readonly NUBE_BINDIR="$NUBE_PREFIX/bin"

echo "==> Instalando scripts en $NUBE_LIBDIR"
install -d -m 0755 "$NUBE_LIBDIR" "$NUBE_LIBDIR/lib" "$NUBE_BINDIR"

for file in \
    init-user.sh \
    add-repository.sh \
    add-domain.sh \
    add-subdomain.sh \
    hook-post-update.sh \
    apply-config.sh \
    no-interactive-login.sh \
    motd-banner.sh \
    lib.sh
do
    install -m 0755 "$NUBE_SRC/$file" "$NUBE_LIBDIR/$file"
done

install -m 0644 "$NUBE_SRC/lib/nube.sh" "$NUBE_LIBDIR/lib/nube.sh"

echo "==> Creando comandos en $NUBE_BINDIR"
ln -sfn "$NUBE_LIBDIR/init-user.sh"           "$NUBE_BINDIR/nube-init-user"
ln -sfn "$NUBE_LIBDIR/add-repository.sh"      "$NUBE_BINDIR/nube-add-repository"
ln -sfn "$NUBE_LIBDIR/add-domain.sh"          "$NUBE_BINDIR/nube-add-domain"
ln -sfn "$NUBE_LIBDIR/add-subdomain.sh"       "$NUBE_BINDIR/nube-add-subdomain"
ln -sfn "$NUBE_LIBDIR/hook-post-update.sh"    "$NUBE_BINDIR/nube-hook-post-update"
ln -sfn "$NUBE_LIBDIR/apply-config.sh"        "$NUBE_BINDIR/nube-apply-config"
ln -sfn "$NUBE_LIBDIR/no-interactive-login.sh" "$NUBE_BINDIR/nube-no-interactive-login"
ln -sfn "$NUBE_LIBDIR/motd-banner.sh"         "$NUBE_BINDIR/nube-motd"

# Limpieza de comandos de la version multi-usuario.
rm -f "$NUBE_BINDIR/nube-add-user" "$NUBE_BINDIR/add-user.sh"

# Limpieza de los alias cortos de versiones anteriores.
rm -f "$NUBE_BINDIR/nr" "$NUBE_BINDIR/nd" "$NUBE_BINDIR/ns"

echo "==> Configuracion"
install -d -m 0755 "$(dirname "$NUBE_CONFIG")"
if [ ! -f "$NUBE_CONFIG" ]; then
    install -m 0644 "$NUBE_SRC/nube.conf.example" "$NUBE_CONFIG"
    echo "    creado $NUBE_CONFIG (revisalo antes de crear el usuario)"
else
    echo "    $NUBE_CONFIG ya existe, no se modifica"
fi

# --- Grupos y permisos -------------------------------------------------------

echo "==> Grupos y permisos"
getent group "$NUBE_SSH_GROUP" >/dev/null 2>&1 || groupadd "$NUBE_SSH_GROUP"
getent group "$NUBE_WEB_GROUP" >/dev/null 2>&1 || groupadd "$NUBE_WEB_GROUP"
if getent group "$NUBE_WEB_GROUP" >/dev/null 2>&1; then
    chgrp "$NUBE_WEB_GROUP" "$NUBE_WEB_ROOT" 2>/dev/null || true
    chmod 2775 "$NUBE_WEB_ROOT" 2>/dev/null || true
fi
install -d -o "$NUBE_WEB_GROUP" -g "$NUBE_WEB_GROUP" -m 2775 "$NUBE_ACME_WEBROOT" 2>/dev/null || true

# El usuario de deploy (grupo www-data) puede instalar ahi sus certificados.
install -d -o root -g "$NUBE_WEB_GROUP" -m 2770 "$NUBE_NGINX_SSL_DIR" 2>/dev/null || true

# Certificado de relleno para que nginx arranque antes de emitir el wildcard.
nube_ensure_ssl_placeholder

# --- nginx -------------------------------------------------------------------

nube_apply_nginx_config "$NUBE_SRC"

# --- fail2ban ----------------------------------------------------------------

nube_apply_fail2ban_config "$NUBE_SRC"

echo
echo "Listo. Comandos disponibles:"
echo "  nube-init-user [clave-publica]      crea el usuario de deploy"
echo "  nube-add-repository <app> [dominio] repositorio bare + hook de la app"
echo "  nube-add-domain <dominio>           dominio propio + certificado TLS"
echo "  nube-add-subdomain <subdominio>     subdominio bajo $NUBE_BASE_DOMAIN"
echo "  nube-apply-config                   vuelve a aplicar esta configuracion"
echo
echo "Siguiente paso: docs/03-instalar-nube.md"
