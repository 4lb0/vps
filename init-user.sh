#!/bin/bash
#
# Crea el (unico) usuario de deploy con:
#   - shell restringido (git-shell)
#   - clave SSH autorizada
#   - usuario de MySQL propio
#   - credenciales cifradas con GPG en ~/secrets.gpg
#
# Uso:
#   sudo nube-init-user [<clave-publica> | --key-file <archivo.pub>]
#
# El nombre y el email salen de /etc/nube/nube.conf (NUBE_USER y
# NUBE_USER_MAIL). Si el usuario ya existe, solo actualiza la clave SSH.
#
# La clave publica tambien se puede pegar a mano en
# ~<usuario>/.ssh/authorized_keys despues de crearlo.

set -euo pipefail

NUBE_SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    NUBE_SELF="$(readlink -f "$NUBE_SELF" 2>/dev/null || printf '%s' "$NUBE_SELF")"
fi
NUBE_DIR="$(cd -- "$(dirname -- "$NUBE_SELF")" && pwd)"
# shellcheck source=/dev/null
. "$NUBE_DIR/lib.sh"

usage() {
    cat >&2 <<EOF
Uso: sudo $(basename "$0") [<clave-publica> | --key-file <archivo.pub>]

Ejemplo:
  sudo $(basename "$0") "ssh-ed25519 AAAA... yo@laptop"
  sudo $(basename "$0") --key-file ~/.ssh/id_ed25519.pub

El usuario que se crea es \$NUBE_USER (ahora: $NUBE_USER), definido en
$NUBE_CONFIG.

Si no pasas la clave, el usuario se crea igual y despues podes agregarla en
/home/$NUBE_USER/.ssh/authorized_keys.
EOF
    exit 1
}

PUBKEY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --key-file)
            [ $# -ge 2 ] || usage
            [ -r "$2" ] || nube_die "no puedo leer la clave publica $2"
            PUBKEY="$(cat "$2")"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            [ -z "$PUBKEY" ] || usage
            PUBKEY="$1"
            shift
            ;;
    esac
done

nube_require_root
nube_valid_name "$NUBE_USER" || nube_die "NUBE_USER invalido: usa minusculas, numeros, guion o guion bajo (max. 32)"
[ "${#NUBE_USER}" -le 18 ] || nube_die "NUBE_USER debe tener 18 caracteres o menos (limite de MySQL)"
nube_require_base_domain

USER_MAIL="$NUBE_USER_MAIL"
[ -n "$USER_MAIL" ] || USER_MAIL="$NUBE_USER@$(hostname -f 2>/dev/null || hostname)"
nube_valid_email "$USER_MAIL" || nube_die "email invalido: $USER_MAIL (defini NUBE_USER_MAIL en $NUBE_CONFIG)"

USER_HOME="/home/$NUBE_USER"
USER_SECRETS="$USER_HOME/secrets.gpg"

getent group "$NUBE_WEB_GROUP" >/dev/null 2>&1 || nube_die "no existe el grupo $NUBE_WEB_GROUP"
[ -n "$NUBE_GIT_SHELL" ] && [ -x "$NUBE_GIT_SHELL" ] || nube_die "git-shell no encontrado (instala git o define NUBE_GIT_SHELL)"
command -v gpg >/dev/null 2>&1 || nube_die "gpg no esta instalado"

install_authorized_key() {
    local key="$1"

    install -d -m 0700 -o "$NUBE_USER" -g "$NUBE_USER" "$USER_HOME/.ssh"
    if [ -f "$USER_HOME/.ssh/authorized_keys" ] && grep -qF "$key" "$USER_HOME/.ssh/authorized_keys"; then
        nube_info "la clave ya estaba en authorized_keys"
        return 0
    fi
    printf '%s\n' "$key" >> "$USER_HOME/.ssh/authorized_keys"
    chown "$NUBE_USER:$NUBE_USER" "$USER_HOME/.ssh/authorized_keys"
    chmod 0600 "$USER_HOME/.ssh/authorized_keys"
    nube_info "clave SSH instalada en $USER_HOME/.ssh/authorized_keys"
}

# --- Usuario de deploy -------------------------------------------------------

if nube_user_exists; then
    nube_warn "el usuario $NUBE_USER ya existe: no lo modifico"
    if [ -n "$PUBKEY" ]; then
        install_authorized_key "$PUBKEY"
    fi
    exit 0
fi

getent group "$NUBE_SSH_GROUP" >/dev/null 2>&1 || {
    nube_warn "no existe el grupo $NUBE_SSH_GROUP; ejecuta install.sh o 'groupadd $NUBE_SSH_GROUP'"
}

if ! mysql --protocol=socket -uroot -e 'SELECT 1' >/dev/null 2>&1; then
    nube_die "no se pudo conectar a MySQL como root. Verifica que este corriendo y que uses sudo."
fi

DB_USER="${NUBE_USER}_$(openssl rand -hex 6)"
DB_PASS="$(openssl rand -base64 32)"

nube_info "creando usuario $NUBE_USER"
useradd --shell "$NUBE_GIT_SHELL" --create-home --user-group "$NUBE_USER"
usermod -aG "$NUBE_WEB_GROUP" "$NUBE_USER"

if getent group "$NUBE_SSH_GROUP" >/dev/null 2>&1; then
    usermod -aG "$NUBE_SSH_GROUP" "$NUBE_USER"
fi

# El home queda 750 y con grupo www-data para que nginx/PHP puedan atravesarlo.
# Los sitios son 2775 y .ssh/secrets quedan 700/600.
chown "$NUBE_USER:$NUBE_WEB_GROUP" "$USER_HOME"
chmod 0750 "$USER_HOME"

nube_info "creando usuario de base de datos $DB_USER"
mysql --protocol=socket -uroot <<SQL
CREATE USER IF NOT EXISTS '$DB_USER'@'$NUBE_MYSQL_HOST' IDENTIFIED BY '$DB_PASS';
SQL

nube_info "generando clave GPG sin passphrase (necesaria para deploys no interactivos)"
runuser -u "$NUBE_USER" -- env HOME="$USER_HOME" \
    gpg --batch --yes --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "$USER_MAIL" default default 0

nube_info "guardando credenciales cifradas en $USER_SECRETS"
printf 'export NUBE_DB_USER=%q\nexport NUBE_DB_PASS=%q\n' "$DB_USER" "$DB_PASS" \
    | runuser -u "$NUBE_USER" -- env HOME="$USER_HOME" \
        gpg --batch --yes --quiet --encrypt --recipient "$USER_MAIL" --output "$USER_SECRETS"
chmod 0600 "$USER_SECRETS"

nube_info "configurando SSH"
install -d -m 0700 -o "$NUBE_USER" -g "$NUBE_USER" "$USER_HOME/.ssh"
if [ -n "$PUBKEY" ]; then
    install_authorized_key "$PUBKEY"
else
    nube_warn "no se recibio clave publica. Agregala en $USER_HOME/.ssh/authorized_keys antes de hacer push."
fi

# Clave de deploy opcional, para que composer pueda clonar dependencias privadas.
if [ ! -f "$USER_HOME/.ssh/id_ed25519" ]; then
    runuser -u "$NUBE_USER" -- env HOME="$USER_HOME" \
        ssh-keygen -q -t ed25519 -N '' -C "$NUBE_USER@$(hostname -f 2>/dev/null || hostname)" \
        -f "$USER_HOME/.ssh/id_ed25519"
fi

nube_info "configurando git-shell"
install -d -m 0755 -o "$NUBE_USER" -g "$NUBE_USER" "$USER_HOME/git-shell-commands"
if [ -x "$NUBE_NO_INTERACTIVE_LOGIN" ]; then
    ln -sfn "$NUBE_NO_INTERACTIVE_LOGIN" "$USER_HOME/git-shell-commands/no-interactive-login"
else
    nube_warn "no se encontro $NUBE_NO_INTERACTIVE_LOGIN; ejecuta install.sh"
fi

mkdir -p "$USER_HOME/www" "$USER_HOME/git"
chown "$NUBE_USER:$NUBE_WEB_GROUP" "$USER_HOME/www" "$USER_HOME/git"
chmod 2775 "$USER_HOME/www"

cat <<EOF

Usuario $NUBE_USER creado.

  Home:        $USER_HOME
  Push SSH:    $NUBE_USER@$(hostname -f 2>/dev/null || hostname)
  Clave GPG:   $USER_MAIL
  DB user:     $DB_USER (password en secrets.gpg)

Siguiente paso:
  sudo runuser -u $NUBE_USER -- nd <dominio>
  sudo runuser -u $NUBE_USER -- nr <app> <dominio> | sudo mysql

Ver docs/04-usuario-y-apps.md
EOF
