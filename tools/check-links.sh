#!/bin/bash
# Verifica que los links relativos de los .md del repo existan.
set -uo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

fail=0
while IFS= read -r file; do
    dir="$(dirname "$file")"
    while IFS= read -r link; do
        case "$link" in
            http*|mailto:*|'#'*|'') continue ;;
        esac
        target="${link%%#*}"
        [ -z "$target" ] && continue
        if [ ! -e "$dir/$target" ]; then
            echo "ROTO: $file -> $link"
            fail=1
        fi
    done < <(grep -oE '\]\([^)]+\)' "$file" | sed 's/^](//; s/)$//')
done < <(find . -name '*.md' -not -path './.git/*')

if [ "$fail" -eq 0 ]; then
    echo "todos los links relativos existen"
else
    exit 1
fi
