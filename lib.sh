#!/bin/bash
# shellcheck shell=bash
#
# Punto de entrada de la libreria compartida de Nube.
# Los scripts hacen source de este archivo; el resuelve la ruta real
# tanto en el repo (lib/nube.sh) como instalado (/usr/local/lib/nube/lib/nube.sh).

NUBE_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ -r "$NUBE_LIB_DIR/lib/nube.sh" ]; then
    # shellcheck source=lib/nube.sh
    . "$NUBE_LIB_DIR/lib/nube.sh"
elif [ -r "$NUBE_LIB_DIR/nube.sh" ]; then
    # shellcheck source=lib/nube.sh
    . "$NUBE_LIB_DIR/nube.sh"
else
    printf 'nube: error: no se encuentra lib/nube.sh junto a %s\n' "$NUBE_LIB_DIR" >&2
    exit 1
fi
