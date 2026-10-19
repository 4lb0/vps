#!/bin/bash
#
# Prueba de humo del deploy: crea un commit, lo pushea y verifica la URL.
#
# Uso:
#   ./test-hook.sh [ruta-a-la-app] [remoto] [url]
#
# Ejemplo:
#   ./test-hook.sh ~/projects/nube-test-app prod https://test.nube.example.com

set -euo pipefail

APP="${1:-$HOME/projects/nube-test-app}"
REMOTE="${2:-prod}"
URL="${3:-}"

[ -d "$APP/.git" ] || { echo "error: $APP no es un repo git" >&2; exit 1; }

cd "$APP"

MESSAGE="Test on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "$MESSAGE" >> test.log
git add test.log
git commit -m "$MESSAGE"
git push "$REMOTE" HEAD

if [ -n "$URL" ]; then
    echo "Esperando a que responda $URL ..."
    for _ in $(seq 1 30); do
        if curl -fsS -o /dev/null "$URL"; then
            echo "ok: $URL"
            exit 0
        fi
        sleep 2
    done
    echo "error: $URL no respondio en 60s" >&2
    exit 1
fi
