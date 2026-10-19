#!/bin/bash
#
# Prepara un subdominio bajo NUBE_BASE_DOMAIN:
#   - crea ~/www/<subdominio>.<base>/public
#   - crea el symlink /var/www/<subdominio>.<base>
#   - deja una pagina inicial
#
# No emite certificado: el comodin *.NUBE_BASE_DOMAIN debe cubrirlo.
#
# Uso:
#   nube-add-subdomain <subdominio>

set -euo pipefail

NUBE_SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    NUBE_SELF="$(readlink -f "$NUBE_SELF" 2>/dev/null || printf '%s' "$NUBE_SELF")"
fi
NUBE_DIR="$(cd -- "$(dirname -- "$NUBE_SELF")" && pwd)"
# shellcheck source=/dev/null
. "$NUBE_DIR/lib.sh"

usage() {
    printf 'Uso: %s <subdominio>\n\nEjemplo: %s mi-app  ->  https://mi-app.%s\n' \
        "$(basename "$0")" "$(basename "$0")" "$NUBE_BASE_DOMAIN" >&2
    exit 1
}

[ $# -eq 1 ] || usage
NAME="$1"
nube_valid_name "$NAME" || nube_die "subdominio invalido: $NAME"
DOMAIN="$NAME.$NUBE_BASE_DOMAIN"

PUBLIC_PATH="$(nube_ensure_web_dir "$DOMAIN")"
nube_info "directorio web: $PUBLIC_PATH"

if [ ! -f "$PUBLIC_PATH/index.html" ] && [ ! -f "$PUBLIC_PATH/index.php" ]; then
    cat > "$PUBLIC_PATH/index.html" <<EOF
<!doctype html>
<html lang="es">
  <head><meta charset="utf-8"><title>$DOMAIN</title></head>
  <body><h1>$DOMAIN</h1><p>Listo para recibir el primer deploy.</p></body>
</html>
EOF
fi

nube_info "listo: $(nube_url "$DOMAIN")"
nube_info "siguiente: nube-add-repository <app> $DOMAIN | sudo mysql"
