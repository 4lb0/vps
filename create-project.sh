#!/bin/bash
#
# Crea un proyecto nuevo en tu maquina (no en el servidor) y configura los
# remotos de git, incluido "prod" para el deploy con Nube.
#
# Uso:
#   create-project.sh <nombre> <template-composer> <origin-url> [<prod-url>]
#
# Ejemplos:
#   create-project.sh blog laravel/laravel \
#     git@github.com:nube/blog.git nube@nube.example.com:git/blog
#
#   create-project.sh api laravel/laravel git@github.com:nube/api.git

set -euo pipefail

usage() {
    cat >&2 <<EOF
Uso: $(basename "$0") <nombre> <template-composer> <origin-url> [<prod-url>]

Ejemplos:
  $(basename "$0") blog laravel/laravel git@github.com:nube/blog.git nube@nube.example.com:git/blog
  $(basename "$0") api  laravel/laravel git@github.com:nube/api.git

El template es cualquier paquete de Composer (laravel/laravel, symfony/skeleton...).
Si no indicas prod-url, igual se puede agregar despues con git remote add.
EOF
    exit 1
}

[ $# -ge 3 ] || usage
[ "$(id -u)" -ne 0 ] || { echo "no lo corras como root: es un script para tu maquina" >&2; exit 1; }

NAME="$1"
TEMPLATE="$2"
ORIGIN_URL="$3"
PROD_URL="${4:-}"

command -v composer >/dev/null 2>&1 || { echo "error: composer no esta instalado" >&2; exit 1; }

if [ -e "$NAME" ]; then
    echo "error: $NAME ya existe" >&2
    exit 1
fi

echo "==> Creando proyecto con composer create-project"
composer create-project "$TEMPLATE" "$NAME" --remove-vcs --no-interaction

cd "$NAME"

if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
fi

if [ -f composer.json ] && [ -f package.json ]; then
    echo "==> Instalando dependencias de npm"
    npm install --no-audit --no-fund
fi

echo "==> Inicializando git"
git init --initial-branch=main
git add .
git commit -m "initial import"

git remote add origin "$ORIGIN_URL" 2>/dev/null || git remote set-url origin "$ORIGIN_URL"
if [ -n "$PROD_URL" ]; then
    git remote add prod "$PROD_URL" 2>/dev/null || git remote set-url prod "$PROD_URL"
fi

echo
echo "Listo. Remotos:"
git remote -v
echo
echo "Siguiente paso: revisar y publicar"
echo "  cd $NAME"
echo "  git push -u origin main"
[ -n "$PROD_URL" ] && echo "  git push prod main"
