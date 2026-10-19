#!/bin/bash
#
# Hook de deploy. Lo invoca ~/git/<app>.git/hooks/post-update en cada push.
#
# Uso interno:
#   nube-hook-post-update <ref> <dominio> <git-dir>
#
# Flujo:
#   1. checkout del ref pusheado en /var/www/<dominio>
#   2. plantilla de .env (reemplaza #NUBE_*#)
#   3. composer install si hay composer.json
#   4. npm ci + build si hay package.json; recarga de PM2 si hay ecosystem
#   5. .venv + pip install si hay requirements.txt o pyproject.toml
#   6. pasos especificos de Laravel
#   7. .nube/deploy opcional
#
# Variables utiles para personalizar:
#   NUBE_SKIP_COMPOSER=1
#   NUBE_SKIP_NPM=1
#   NUBE_SKIP_PYTHON=1
#   NUBE_SKIP_MIGRATIONS=1
#   NUBE_SKIP_ARTISAN_CACHE=1

set -Eeuo pipefail

NUBE_REFS="${1:-}"
NUBE_DOMAIN="${2:-}"
NUBE_GIT_DIR="${3:-}"

[ -n "$NUBE_REFS" ] && [ -n "$NUBE_DOMAIN" ] && [ -n "$NUBE_GIT_DIR" ] || {
    echo "uso: nube-hook-post-update <ref> <dominio> <git-dir>" >&2
    exit 1
}

NUBE_SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    NUBE_SELF="$(readlink -f "$NUBE_SELF" 2>/dev/null || printf '%s' "$NUBE_SELF")"
fi
NUBE_DIR="$(cd -- "$(dirname -- "$NUBE_SELF")" && pwd)"
# shellcheck source=/dev/null
. "$NUBE_DIR/lib.sh"

NUBE_PATH="$(nube_ensure_web_dir "$NUBE_DOMAIN")"
NUBE_APP_ROOT="$HOME/www/$NUBE_DOMAIN"
NUBE_SLUG="$(nube_slug "$NUBE_DOMAIN")"
NUBE_URL="$(nube_url "$NUBE_DOMAIN")"

# Descifra NUBE_DB_USER / NUBE_DB_PASS para el .env y Laravel.
nube_load_secrets

readonly NUBE_OK="\e[32;1m ok\e[0m"
readonly NUBE_ERROR="\e[31;1m error\e[0m"
readonly NUBE_UPLOAD="Haciendo el deploy a \e[34m$NUBE_DOMAIN\e[0m"
readonly NUBE_PROCESS_ERROR="\e[31;1mError de deploy.\e[0m
Revisa el log: $NUBE_DEPLOY_LOG
Si el problema persiste, reportalo con el dominio, el commit y las ultimas lineas del log."

welcome() {
    echo -e "☁️  \e[35;1mNube\e[0m - $(nube_url "$NUBE_DOMAIN") 🚀"
    echo -e "$NUBE_UPLOAD"
    echo -e "ref: $NUBE_REFS"
}

error_report() {
    local code=$?
    echo -e "$NUBE_PROCESS_ERROR" >&2
    exit "$code"
}
trap error_report ERR

if [ -n "$NUBE_DEPLOY_LOG" ]; then
    touch "$NUBE_DEPLOY_LOG" 2>/dev/null || true
    exec > >(tee -a "$NUBE_DEPLOY_LOG") 2>&1
fi

echo
echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) deploy $NUBE_DOMAIN $NUBE_REFS ==="

welcome

# --- Checkout ----------------------------------------------------------------

[ -d "$NUBE_GIT_DIR" ] || nube_die "no existe el repositorio $NUBE_GIT_DIR"
[ -d "$NUBE_PATH" ] || nube_die "no existe el directorio web $NUBE_PATH"

nube_info "actualizando archivos"
git --work-tree="$NUBE_APP_ROOT" --git-dir="$NUBE_GIT_DIR" checkout -f -q "$NUBE_REFS"

cd "$NUBE_APP_ROOT"

# --- .env --------------------------------------------------------------------

nube_info "preparando .env"
if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
    echo -e "  plantilla copiada$NUBE_OK"
fi

if [ -f .env ]; then
    sed -i "s@#NUBE_ROOT#@$NUBE_APP_ROOT@g" .env
    sed -i "s@#NUBE_URL#@$NUBE_URL@g" .env
    sed -i "s@#NUBE_DB_CONN#@mysql@g" .env
    sed -i "s@#NUBE_DB_HOST#@$NUBE_MYSQL_HOST@g" .env
    sed -i "s@#NUBE_DB_PORT#@$NUBE_MYSQL_PORT@g" .env
    sed -i "s@#NUBE_DB_NAME#@$NUBE_SLUG@g" .env
    if [ -n "${NUBE_DB_USER:-}" ]; then
        sed -i "s@#NUBE_DB_USER#@$NUBE_DB_USER@g" .env
        sed -i "s@#NUBE_DB_PASS#@$NUBE_DB_PASS@g" .env
    fi
fi

# --- Composer ----------------------------------------------------------------

if [ -f composer.json ] && [ "${NUBE_SKIP_COMPOSER:-0}" != "1" ]; then
    command -v composer >/dev/null 2>&1 || nube_die "composer no esta instalado en el servidor"
    echo -e -n "Instalando dependencias de composer..."
    composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --quiet
    echo -e "$NUBE_OK"
fi

# --- Node --------------------------------------------------------------------

node_dependencies() {
    command -v npm >/dev/null 2>&1 \
        || nube_die "hay package.json pero npm no esta instalado en el servidor"

    echo -e -n "Instalando dependencias de npm..."
    if [ -f package-lock.json ]; then
        npm ci --no-audit --no-fund --loglevel=error
    else
        npm install --no-audit --no-fund --loglevel=error
    fi
    echo -e "$NUBE_OK"

    if node -e 'process.exit(require("./package.json").scripts?.build ? 0 : 1)' 2>/dev/null; then
        echo -e -n "Compilando con npm..."
        npm run build --silent
        echo -e "$NUBE_OK"
    fi
}

node_reload() {
    [ -f ecosystem.config.js ] || return 0

    if ! command -v pm2 >/dev/null 2>&1; then
        nube_warn "hay ecosystem.config.js pero pm2 no esta instalado; el proceso no se reinicia solo"
        return 0
    fi

    echo -e -n "Recargando procesos con PM2..."
    pm2 startOrReload ecosystem.config.js --update-env >/dev/null
    pm2 save >/dev/null
    echo -e "$NUBE_OK"
}

if [ -f package.json ]; then
    echo -e "Stack encontrado: \e[1mNode\e[0m"
    [ "${NUBE_SKIP_NPM:-0}" = "1" ] || node_dependencies
    node_reload
fi

# --- Python ------------------------------------------------------------------

python_dependencies() {
    command -v python3 >/dev/null 2>&1 \
        || nube_die "hay requirements.txt o pyproject.toml pero python3 no esta instalado"

    local python="$NUBE_APP_ROOT/.venv/bin/python"
    local pip="$NUBE_APP_ROOT/.venv/bin/pip"

    if [ ! -x "$python" ]; then
        echo -e -n "Creando entorno virtual..."
        python3 -m venv .venv || nube_die "no se pudo crear .venv (instala python3-venv)"
        echo -e "$NUBE_OK"
    fi

    echo -e -n "Instalando dependencias de Python..."
    "$pip" install --quiet --upgrade pip
    if [ -f requirements.txt ]; then
        "$pip" install --quiet -r requirements.txt
    else
        "$pip" install --quiet .
    fi
    echo -e "$NUBE_OK"
}

if [ -f requirements.txt ] || [ -f pyproject.toml ]; then
    echo -e "Stack encontrado: \e[1mPython\e[0m"
    [ "${NUBE_SKIP_PYTHON:-0}" = "1" ] || python_dependencies
fi

# --- Laravel -----------------------------------------------------------------

laravel_dotenv() {
    [ -f .env ] || nube_die "Laravel necesita un .env (no hay .env ni .env.example)"

    sed -i "s#^APP_URL=.*#APP_URL=$NUBE_URL#g" .env
    sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/g" .env
    sed -i "s/^DB_HOST=.*/DB_HOST=$NUBE_MYSQL_HOST/g" .env
    sed -i "s/^DB_PORT=.*/DB_PORT=$NUBE_MYSQL_PORT/g" .env
    sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$NUBE_SLUG/g" .env
    sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$NUBE_DB_USER/g" .env
    sed -i "s@^DB_PASSWORD=.*@DB_PASSWORD=$NUBE_DB_PASS@g" .env

    if ! grep -q '^APP_KEY=base64:' .env; then
        echo -e -n "Generando APP_KEY..."
        php artisan key:generate --force --no-interaction --quiet
        echo -e "$NUBE_OK"
    fi
}

laravel_permissions() {
    local dir
    for dir in storage bootstrap/cache; do
        [ -d "$dir" ] || continue
        chgrp -R "$NUBE_WEB_GROUP" "$dir"
        chmod -R g+rwX "$dir"
    done
}

laravel_max_key_workaround() {
    local provider="app/Providers/AppServiceProvider.php"
    [ -f "$provider" ] || return 0
    grep -q 'Schema::defaultStringLength' "$provider" && return 0

    # Workaround historico para MySQL con indices de 191 caracteres.
    sed -i '/boot()/{N;/}/a\        \Illuminate\Support\Facades\Schema::defaultStringLength(191);' "$provider" \
        || nube_warn "no se pudo aplicar el workaround de Schema::defaultStringLength"
}

laravel_cache() {
    [ "${NUBE_SKIP_ARTISAN_CACHE:-0}" = "1" ] && return 0

    echo -e -n "Cacheando configuracion..."
    php artisan config:cache --no-interaction --quiet && echo -e "$NUBE_OK" || echo -e "$NUBE_ERROR"
    echo -e -n "Cacheando rutas..."
    php artisan route:cache --no-interaction --quiet && echo -e "$NUBE_OK" || echo -e "$NUBE_ERROR"
    echo -e -n "Cacheando vistas..."
    php artisan view:cache --no-interaction --quiet && echo -e "$NUBE_OK" || echo -e "$NUBE_ERROR"
}

if [ -f artisan ]; then
    echo -e "Framework encontrado: \e[1mLaravel\e[0m"

    [ -n "${NUBE_DB_USER:-}" ] || nube_die "faltan credenciales de DB en $NUBE_SECRETS_FILE"

    laravel_dotenv
    laravel_permissions
    laravel_max_key_workaround
    laravel_cache

    if [ "${NUBE_SKIP_MIGRATIONS:-0}" != "1" ]; then
        echo "Corriendo migraciones..."
        php artisan migrate --force --no-interaction
    fi
fi

# --- Hook propio de la app ----------------------------------------------------

if [ -x .nube/deploy ]; then
    echo "Ejecutando .nube/deploy..."
    NUBE_DOMAIN="$NUBE_DOMAIN" \
    NUBE_PATH="$NUBE_APP_ROOT" \
    NUBE_URL="$NUBE_URL" \
    NUBE_REFS="$NUBE_REFS" \
    NUBE_DB_USER="${NUBE_DB_USER:-}" \
    NUBE_DB_PASS="${NUBE_DB_PASS:-}" \
        ./.nube/deploy
fi

echo
echo -e "\e[1;32mListo\e[0m → 🔗 \e[34;4m$NUBE_URL\e[0m"
echo -e "Log: $NUBE_DEPLOY_LOG"
