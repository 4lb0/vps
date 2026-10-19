#!/bin/bash
#
# Prepara un VPS recien instalado para usar Nube:
#
#   1. deja /etc/nube/nube.conf con tu dominio base y usuario;
#   2. instala la configuracion (nginx, fail2ban y comandos);
#   3. crea el usuario de deploy y le instala tu clave SSH;
#   4. crea el repositorio del servidor ($NUBE_SERVER_REPO) con un hook
#      post-receive: los push ahi aplican la configuracion (/etc/nginx, ...);
#   5. habilita el sudoers acotado que necesita ese hook.
#
# Uso:
#   sudo ./bootstrap.sh --base-domain nube.example.com \
#                       --email yo@example.com \
#                       --ssh-key-file ~/.ssh/id_ed25519.pub
#
# Es idempotente: volver a correrlo no rompe nada.

set -euo pipefail

NUBE_SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    NUBE_SELF="$(readlink -f "$NUBE_SELF" 2>/dev/null || printf '%s' "$NUBE_SELF")"
fi
NUBE_SRC="$(cd -- "$(dirname -- "$NUBE_SELF")" && pwd)"
# shellcheck source=/dev/null
. "$NUBE_SRC/lib.sh"

usage() {
    cat >&2 <<EOF
Uso: sudo $(basename "$0") [opciones]

  --base-domain <dominio>   Dominio base de las apps (NUBE_BASE_DOMAIN)
  --user <usuario>          Usuario de deploy (default: nube)
  --email <email>           Email del usuario de deploy (clave GPG)
  --ssh-key <clave>         Clave publica que puede hacer push
  --ssh-key-file <archivo>  Archivo con la clave publica
  --php <version>           Version de PHP (default: 8.3)

Ejemplo:
  sudo $(basename "$0") --base-domain nube.example.com \\
      --email yo@example.com --ssh-key-file ~/.ssh/id_ed25519.pub
EOF
    exit 1
}

declare -A WANT=()
PUBKEY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base-domain) WANT[NUBE_BASE_DOMAIN]="${2:-}"; shift 2 ;;
        --user)        WANT[NUBE_USER]="${2:-}";        shift 2 ;;
        --email)       WANT[NUBE_USER_MAIL]="${2:-}";   shift 2 ;;
        --php)         WANT[NUBE_PHP_VERSION]="${2:-}"; shift 2 ;;
        --ssh-key)     PUBKEY="${2:-}";                 shift 2 ;;
        --ssh-key-file)
            [ -r "${2:-}" ] || nube_die "no puedo leer la clave publica ${2:-}"
            PUBKEY="$(cat "$2")"; shift 2 ;;
        -h|--help)     usage ;;
        *)             usage ;;
    esac
done

nube_require_root

# --- 1. Configuracion --------------------------------------------------------

install -d -m 0755 "$(dirname "$NUBE_CONFIG")"
if [ ! -f "$NUBE_CONFIG" ]; then
    install -m 0644 "$NUBE_SRC/nube.conf.example" "$NUBE_CONFIG"
    nube_info "creado $NUBE_CONFIG"
fi

for key in "${!WANT[@]}"; do
    [ -n "${WANT[$key]}" ] || continue
    nube_conf_set "$key" "${WANT[$key]}"
done

# Releer la configuracion con los valores nuevos.
# shellcheck source=/dev/null
. "$NUBE_CONFIG"
NUBE_USER="${NUBE_USER:-nube}"
NUBE_BASE_DOMAIN="${NUBE_BASE_DOMAIN:-}"
NUBE_SERVER_REPO="${NUBE_SERVER_REPO:-/home/$NUBE_USER/git/nube.git}"
NUBE_SERVER_SRC="${NUBE_SERVER_SRC:-/srv/nube}"
NUBE_SERVER_REF="${NUBE_SERVER_REF:-main}"
NUBE_APPLY_BIN="${NUBE_APPLY_BIN:-/usr/local/bin/nube-apply-config}"
NUBE_SSH_GROUP="${NUBE_SSH_GROUP:-nube}"

nube_require_base_domain

# --- 2. Instalacion ----------------------------------------------------------

"$NUBE_SRC/install.sh" "$NUBE_SRC"

# --- 3. Usuario de deploy ----------------------------------------------------

if [ -n "$PUBKEY" ]; then
    "$NUBE_SRC/init-user.sh" "$PUBKEY"
else
    nube_warn "sin --ssh-key-file: el usuario $NUBE_USER se crea igual, pero no va a poder hacer push"
    "$NUBE_SRC/init-user.sh"
fi

# --- 4. Repositorio del servidor --------------------------------------------

echo "==> Repositorio del servidor en $NUBE_SERVER_REPO"
install -d -o "$NUBE_USER" -g "$NUBE_USER" -m 0755 "$(dirname "$NUBE_SERVER_REPO")"
if [ ! -d "$NUBE_SERVER_REPO" ]; then
    git init --bare --quiet --initial-branch="$NUBE_SERVER_REF" "$NUBE_SERVER_REPO"
fi
install -m 0755 "$NUBE_SRC/server/post-receive" "$NUBE_SERVER_REPO/hooks/post-receive"
chown -R "$NUBE_USER:$NUBE_USER" "$NUBE_SERVER_REPO"

# --- 5. sudoers acotado ------------------------------------------------------

echo "==> Permisos para aplicar la configuracion"
SUDOERS=/etc/sudoers.d/nube
TMP_SUDOERS="$(mktemp)"
cat > "$TMP_SUDOERS" <<EOF
# Generado por bootstrap.sh de Nube. No editar a mano.
# El usuario de deploy puede aplicar la configuracion del servidor con un
# push a su repositorio ($NUBE_SERVER_REPO) y recargar nginx al emitir
# certificados con "nube-add-domain".
$NUBE_USER ALL=(root) NOPASSWD: $NUBE_APPLY_BIN, /usr/bin/systemctl reload nginx, /usr/sbin/nginx -t
EOF
if visudo -c -q -f "$TMP_SUDOERS" 2>/dev/null; then
    install -m 0440 -o root -g root "$TMP_SUDOERS" "$SUDOERS"
else
    nube_warn "sudoers invalido; revisa $TMP_SUDOERS y copialo a mano en $SUDOERS"
fi
rm -f "$TMP_SUDOERS"

# --- Resumen -----------------------------------------------------------------

HOSTNAME_F="$(hostname -f 2>/dev/null || hostname)"
cat <<EOF

Nube quedo instalado.

  Dominio base:    $NUBE_BASE_DOMAIN
  Usuario:         $NUBE_USER ($HOSTNAME_F)
  Apps:            https://<app>.$NUBE_BASE_DOMAIN
  Config del VPS:  $NUBE_SERVER_REPO

Desde tu maquina, sincroniza este repositorio (tu fork) con el servidor:

  git remote add server $NUBE_USER@$HOSTNAME_F:git/nube
  git push server main

Siguiente paso: docs/04-usuario-y-apps.md para crear la primera app.
EOF
