#!/bin/bash
#
# Banner de bienvenida (MOTD) para el servidor.

[ -r /etc/nube/nube.conf ] && . /etc/nube/nube.conf

HOST="$(hostname -f 2>/dev/null || hostname)"
echo -e "☁️  \e[35;1mNube\e[0m en \e[1m$HOST\e[0m"
[ -n "${NUBE_BASE_DOMAIN:-}" ] && echo -e "   apps: \e[34m*.$NUBE_BASE_DOMAIN\e[0m"
echo ""
