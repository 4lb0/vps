#!/bin/bash
#
# Crea un usuario de deploy con:
#   - shell restringido (git-shell)
#   - clave SSH autorizada
#   - usuario de MySQL propio
#   - credenciales cifradas con GPG en ~/secrets.gpg
#
# Uso:
#   sudo add-user.sh <usuario> <email> [<clave-publica>]
#
# La clave publica tambien se puede pegar en ~usuario/.ssh/authorized_keys
# despues de crear el usuario.

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
Uso: sudo $(basename "$0") <usuario> <email> [<clave-publica>]

Ejemplo:
  sudo $(basename "$0") juan juan@example.com "ssh-ed25519 AAAA... juan@laptop"

Si no pasas la clave, el usuario se crea igual y despues podes agregarla en
/home/<usuario>/.ssh/authorized_keys.
EOF
    exit 1
}

[ $# -ge 2 ] || usage
[ "$(id -u)" -eq 0 ] || nube_die "ejecuta este script como root"

NEW_USER="$1"
NEW_USER_MAIL="$2"
NEW_USER_PUBKEY="${3:-}"
NEW_USER_HOME="/home/$NEW_USER"
NEW_USER_SECRETS="$NEW_USER_HOME/secrets.gpg"

nube_valid_name "$NEW_USER" || nube_die "nombre de usuario invalido: usa minusculas, numeros, guion o guion bajo (max. 32)"
[ "${#NEW_USER}" -le 18 ] || nube_die "el usuario debe tener 18 caracteres o menos (limite de MySQL)"
nube_valid_email "$NEW_USER_MAIL" || nube_die "email invalido: $NEW_USER_MAIL"

id "$NEW_USER" >/dev/null 2>&1 && nube_die "el usuario $NEW_USER ya existe"
getent group "$NUBE_WEB_GROUP" >/dev/null 2>&1 || nube_die "no existe el grupo $NUBE_WEB_GROUP"
[ -n "$NUBE_GIT_SHELL" ] && [ -x "$NUBE_GIT_SHELL" ] || nube_die "git-shell no encontrado (instala git o define NUBE_GIT_SHELL)"

if ! mysql --protocol=socket -uroot -e 'SELECT 1' >/dev/null 2>&1; then
    nube_die "no se pudo conectar a MySQL como root. Verifica que este corriendo y que uses sudo."
fi

DB_USER="${NEW_USER}_$(openssl rand -hex 6)"
DB_PASS="$(openssl rand -base64 32)"

nube_info "creando usuario $NEW_USER"
useradd --shell "$NUBE_GIT_SHELL" --create-home --user-group "$NEW_USER"
usermod -aG "$NUBE_WEB_GROUP" "$NEW_USER"

if getent group "$NUBE_SSH_GROUP" >/dev/null 2>&1; then
    usermod -aG "$NUBE_SSH_GROUP" "$NEW_USER"
else
    nube_warn "no existe el grupo $NUBE_SSH_GROUP; ejecuta install.sh o 'groupadd $NUBE_SSH_GROUP' si vas a usar AllowGroups en sshd"
fi

# El home queda 750 y con grupo www-data para que nginx/PHP puedan atravesarlo.
# El resto de usuarios del grupo no deberia poder leer archivos privados:
# los sitios son 2775 y .ssh/secrets quedan 700/600.
chown "$NEW_USER:$NUBE_WEB_GROUP" "$NEW_USER_HOME"
chmod 0750 "$NEW_USER_HOME"

nube_info "creando usuario de base de datos $DB_USER"
mysql --protocol=socket -uroot <<SQL
CREATE USER IF NOT EXISTS '$DB_USER'@'$NUBE_MYSQL_HOST' IDENTIFIED BY '$DB_PASS';
SQL

nube_info "generando clave GPG sin passphrase (necesaria para deploys no interactivos)"
runuser -u "$NEW_USER" -- env HOME="$NEW_USER_HOME" \
    gpg --batch --yes --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "$NEW_USER_MAIL" default default 0

nube_info "guardando credenciales cifradas en $NEW_USER_SECRETS"
printf 'export NUBE_DB_USER=%q\nexport NUBE_DB_PASS=%q\n' "$DB_USER" "$DB_PASS" \
    | runuser -u "$NEW_USER" -- env HOME="$NEW_USER_HOME" \
        gpg --batch --yes --quiet --encrypt --recipient "$NEW_USER_MAIL" --output "$NEW_USER_SECRETS"
chmod 0600 "$NEW_USER_SECRETS"

nube_info "configurando SSH"
install -d -m 0700 -o "$NEW_USER" -g "$NEW_USER" "$NEW_USER_HOME/.ssh"
if [ -n "$NEW_USER_PUBKEY" ]; then
    printf '%s\n' "$NEW_USER_PUBKEY" > "$NEW_USER_HOME/.ssh/authorized_keys"
    chown "$NEW_USER:$NEW_USER" "$NEW_USER_HOME/.ssh/authorized_keys"
    chmod 0600 "$NEW_USER_HOME/.ssh/authorized_keys"
else
    nube_warn "no se recibio clave publica. Agregala en $NEW_USER_HOME/.ssh/authorized_keys antes de hacer push."
fi

# Clave de deploy opcional, para que composer pueda clonar dependencias privadas.
if [ ! -f "$NEW_USER_HOME/.ssh/id_ed25519" ]; then
    runuser -u "$NEW_USER" -- env HOME="$NEW_USER_HOME" \
        ssh-keygen -q -t ed25519 -N '' -C "$NEW_USER@$(hostname -f 2>/dev/null || hostname)" \
        -f "$NEW_USER_HOME/.ssh/id_ed25519"
fi

nube_info "configurando git-shell"
install -d -m 0755 -o "$NEW_USER" -g "$NEW_USER" "$NEW_USER_HOME/git-shell-commands"
if [ -x "$NUBE_NO_INTERACTIVE_LOGIN" ]; then
    ln -sfn "$NUBE_NO_INTERACTIVE_LOGIN" "$NEW_USER_HOME/git-shell-commands/no-interactive-login"
else
    nube_warn "no se encontro $NUBE_NO_INTERACTIVE_LOGIN; ejecuta install.sh"
fi

mkdir -p "$NEW_USER_HOME/www" "$NEW_USER_HOME/git"
chown "$NEW_USER:$NUBE_WEB_GROUP" "$NEW_USER_HOME/www" "$NEW_USER_HOME/git"
chmod 2775 "$NEW_USER_HOME/www"

cat <<EOF

Usuario $NEW_USER creado.

  Home:        $NEW_USER_HOME
  Deploy SSH:  $NEW_USER@$(hostname -f 2>/dev/null || hostname)
  Clave GPG:   $NEW_USER_MAIL
  DB user:     $DB_USER (password en secrets.gpg)

Siguiente paso:
  sudo runuser -u $NEW_USER -- nd <dominio>
  sudo runuser -u $NEW_USER -- nr <app> <dominio> | sudo mysql

Ver docs/04-usuarios-y-aplicaciones.md
EOF
