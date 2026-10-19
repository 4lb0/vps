#!/bin/bash
#
# Aplica la configuracion del servidor a partir del repositorio del servidor.
#
#   sudo nube-apply-config
#
# Lo invoca el hook post-receive de $NUBE_SERVER_REPO cada vez que se hace
# push. Tambien se puede correr a mano para volver a aplicar la configuracion
# sin push (por ejemplo, despues de cambiar /etc/nube/nube.conf).
#
# Hace un checkout de la rama $NUBE_SERVER_REF en $NUBE_SERVER_SRC y ejecuta
# el install.sh de esa copia, que es el que copia la configuracion a
# /usr/local, /etc/nginx y /etc/fail2ban.

set -euo pipefail

NUBE_SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    NUBE_SELF="$(readlink -f "$NUBE_SELF" 2>/dev/null || printf '%s' "$NUBE_SELF")"
fi
NUBE_DIR="$(cd -- "$(dirname -- "$NUBE_SELF")" && pwd)"
# shellcheck source=/dev/null
. "$NUBE_DIR/lib.sh"

nube_require_root

[ -d "$NUBE_SERVER_REPO" ] || \
    nube_die "no existe el repositorio del servidor $NUBE_SERVER_REPO (corre bootstrap.sh)"

command -v git >/dev/null 2>&1 || nube_die "git no esta instalado"

install -d -m 0755 "$NUBE_SERVER_SRC"

nube_info "actualizando $NUBE_SERVER_SRC desde $NUBE_SERVER_REPO ($NUBE_SERVER_REF)"
if ! git --git-dir="$NUBE_SERVER_REPO" --work-tree="$NUBE_SERVER_SRC" \
        checkout -f -q "$NUBE_SERVER_REF" 2>/dev/null; then
    nube_die "no pude hacer checkout de $NUBE_SERVER_REF en $NUBE_SERVER_SRC (¿ya hiciste 'git push server main'? Si no, usa 'sudo ./install.sh' desde el clon)"
fi

exec bash "$NUBE_SERVER_SRC/install.sh" "$NUBE_SERVER_SRC"
