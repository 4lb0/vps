#!/bin/bash
#
# Crea (o actualiza) el repositorio bare y el hook de deploy de una app.
#
# Uso:
#   nube-add-repository <app> [dominio]
#
# Si no se indica dominio, se usa el nombre de la app.
# Imprime por stdout el SQL de MySQL; los mensajes van a stderr para que
# se pueda encadenar:
#
#   nube-add-repository mi-app mi-app.example.com | sudo mysql
#
# Este comando se ejecuta como el usuario de deploy: el dueno de los
# repositorios y de los sitios. No se ejecuta como root.

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
Uso: $(basename "$0") <app> [dominio]

Ejemplos:
  $(basename "$0") blog blog.example.com
  $(basename "$0") blog blog.$NUBE_BASE_DOMAIN
  $(basename "$0") blog            # usa "blog" como dominio
EOF
    exit 1
}

[ $# -ge 1 ] || usage

NAME="$1"
DOMAIN="${2:-$1}"
REPO_DIR="$HOME/git/$NAME"
HOOK_FILE="$REPO_DIR/hooks/post-update"
DB_NAME="$(nube_slug "$DOMAIN")"

nube_valid_name "$NAME" || nube_die "nombre de app invalido: $NAME"
nube_valid_domain "$DOMAIN" || nube_die "dominio invalido: $DOMAIN"

if [ ! -d "$REPO_DIR" ]; then
    nube_info "creando repositorio $REPO_DIR"
    mkdir -p "$HOME/git"
    git init --bare --quiet "$REPO_DIR"
else
    nube_info "actualizando repositorio existente $REPO_DIR"
fi

nube_info "escribiendo hook post-update"
cat > "$HOOK_FILE" <<EOF
#!/bin/bash
# Generado por nube-add-repository el $(date -u +%Y-%m-%dT%H:%M:%SZ)
# No editar a mano: volve a ejecutar nube-add-repository para regenerarlo.
exec "$NUBE_HOOK_BIN" "\$1" "$DOMAIN" "$REPO_DIR"
EOF
chmod 0755 "$HOOK_FILE"

# Asegura el directorio de deploy y el symlink en /var/www.
nube_ensure_web_dir "$DOMAIN" >/dev/null

nube_load_secrets
if [ -z "${NUBE_DB_USER:-}" ]; then
    nube_warn "no hay credenciales en $NUBE_SECRETS_FILE; no se puede generar el SQL"
    exit 0
fi

cat <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$NUBE_DB_USER'@'$NUBE_MYSQL_HOST';
FLUSH PRIVILEGES;
SQL
