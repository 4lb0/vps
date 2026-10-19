#!/bin/bash
#
# Prepara un dominio propio:
#   - crea ~/www/<dominio>/public
#   - crea el symlink /var/www/<dominio>
#   - deja una pagina inicial
#   - emite el certificado TLS con acme.sh (segun NUBE_ACME_MODE)
#
# Uso:
#   nube-add-domain <dominio>
#
# Ejecutar como el usuario dueno de la app.

set -euo pipefail

NUBE_SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    NUBE_SELF="$(readlink -f "$NUBE_SELF" 2>/dev/null || printf '%s' "$NUBE_SELF")"
fi
NUBE_DIR="$(cd -- "$(dirname -- "$NUBE_SELF")" && pwd)"
# shellcheck source=/dev/null
. "$NUBE_DIR/lib.sh"

usage() {
    printf 'Uso: %s <dominio>\n\nEjemplo: %s app.example.com\n' "$(basename "$0")" "$(basename "$0")" >&2
    exit 1
}

[ $# -eq 1 ] || usage
DOMAIN="$1"
nube_valid_domain "$DOMAIN" || nube_die "dominio invalido: $DOMAIN"

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

issue_certificate() {
    local acme="$NUBE_ACME_HOME/acme.sh"
    local cert_dir="$NUBE_NGINX_SSL_DIR/$DOMAIN"
    local -a reload_args=()

    case "$NUBE_ACME_MODE" in
        none)
            nube_info "NUBE_ACME_MODE=none: no se emite certificado"
            return 0
            ;;
        stateless)
            [ -x "$acme" ] || { nube_warn "no se encuentra $acme"; return 1; }
            "$acme" --issue -d "$DOMAIN" -w "$PUBLIC_PATH" --stateless
            ;;
        webroot)
            [ -x "$acme" ] || { nube_warn "no se encuentra $acme"; return 1; }
            mkdir -p "$NUBE_ACME_WEBROOT"
            "$acme" --issue -d "$DOMAIN" -w "$NUBE_ACME_WEBROOT"
            ;;
        *)
            nube_die "NUBE_ACME_MODE invalido: $NUBE_ACME_MODE (usa webroot, stateless o none)"
            ;;
    esac

    # Instala el certificado en una ruta estable para nginx.
    if mkdir -p "$cert_dir" 2>/dev/null && [ -w "$cert_dir" ]; then
        if sudo -n -l /usr/bin/systemctl reload nginx >/dev/null 2>&1; then
            reload_args=(--reloadcmd "sudo -n systemctl reload nginx")
        fi
        "$acme" --install-cert -d "$DOMAIN" "${reload_args[@]}" \
            --key-file "$cert_dir/key.pem" \
            --fullchain-file "$cert_dir/fullchain.pem"
    else
        nube_warn "no se pudo escribir en $cert_dir; nginx no encontrara el certificado"
        nube_warn "crea $NUBE_NGINX_SSL_DIR con grupo $NUBE_WEB_GROUP: chgrp $NUBE_WEB_GROUP $NUBE_NGINX_SSL_DIR && chmod 2770 $NUBE_NGINX_SSL_DIR"
    fi
}

issue_certificate || nube_warn "no se pudo emitir el certificado. Revisa DNS/acme.sh y volve a intentar."
nube_reload_nginx || true

nube_info "listo: $(nube_url "$DOMAIN")"
nube_info "repositorio: git remote add prod $NUBE_USER@$(hostname -f 2>/dev/null || hostname):git/<app>"
