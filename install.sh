#!/bin/bash
#
# Instala los comandos de Nube en el sistema.
#
#   sudo ./install.sh
#
# Es idempotente: se puede volver a ejecutar despues de un git pull.
# No toca nginx, MySQL ni los usuarios existentes.

set -euo pipefail

readonly NUBE_PREFIX="${NUBE_PREFIX:-/usr/local}"
readonly NUBE_LIBDIR="$NUBE_PREFIX/lib/nube"
readonly NUBE_BINDIR="$NUBE_PREFIX/bin"
readonly NUBE_CONFDIR="/etc/nube"
readonly NUBE_CONF="$NUBE_CONFDIR/nube.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo "error: ejecuta este script como root (sudo ./install.sh)" >&2
    exit 1
fi

NUBE_SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Instalando archivos en $NUBE_LIBDIR"
install -d -m 0755 "$NUBE_LIBDIR" "$NUBE_LIBDIR/lib" "$NUBE_BINDIR"

for file in \
    add-user.sh \
    add-repository.sh \
    add-domain.sh \
    add-subdomain.sh \
    hook-post-update.sh \
    no-interactive-login.sh \
    motd-banner.sh \
    lib.sh
do
    install -m 0755 "$NUBE_SRC/$file" "$NUBE_LIBDIR/$file"
done

install -m 0644 "$NUBE_SRC/lib/nube.sh" "$NUBE_LIBDIR/lib/nube.sh"

echo "==> Creando comandos"
ln -sfn "$NUBE_LIBDIR/add-user.sh"        "$NUBE_BINDIR/nube-add-user"
ln -sfn "$NUBE_LIBDIR/add-user.sh"        "$NUBE_BINDIR/add-user.sh"
ln -sfn "$NUBE_LIBDIR/add-repository.sh"  "$NUBE_BINDIR/nr"
ln -sfn "$NUBE_LIBDIR/add-domain.sh"      "$NUBE_BINDIR/nd"
ln -sfn "$NUBE_LIBDIR/add-subdomain.sh"   "$NUBE_BINDIR/ns"
ln -sfn "$NUBE_LIBDIR/hook-post-update.sh" "$NUBE_BINDIR/nube-hook-post-update"
ln -sfn "$NUBE_LIBDIR/no-interactive-login.sh" "$NUBE_BINDIR/nube-no-interactive-login"
ln -sfn "$NUBE_LIBDIR/motd-banner.sh"     "$NUBE_BINDIR/nube-motd"

echo "==> Configuracion"
install -d -m 0755 "$NUBE_CONFDIR"
if [ ! -f "$NUBE_CONF" ]; then
    install -m 0644 "$NUBE_SRC/nube.conf.example" "$NUBE_CONF"
    echo "    creado $NUBE_CONF (revisalo antes de crear usuarios)"
else
    echo "    $NUBE_CONF ya existe, no se modifica"
fi

echo "==> Grupos y permisos"
getent group nube >/dev/null 2>&1 || groupadd nube
if getent group www-data >/dev/null 2>&1; then
    chgrp www-data /var/www 2>/dev/null || true
    chmod 2775 /var/www 2>/dev/null || true
fi
install -d -o www-data -g www-data -m 2775 /var/www/acme 2>/dev/null || true

# Los usuarios de deploy (grupo www-data) pueden instalar ahi sus certificados.
install -d -o root -g www-data -m 2770 /etc/nginx/ssl 2>/dev/null || true

echo
echo "Listo. Comandos disponibles:"
echo "  nube-add-user <usuario> <email> [clave-publica]"
echo "  nr <app> [dominio]"
echo "  nd <dominio>"
echo "  ns <subdominio>"
echo
echo "Siguiente paso: edita $NUBE_CONF y sigue docs/03-instalar-nube.md"
