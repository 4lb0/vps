#!/bin/bash
#
# Mensaje que ve el usuario de deploy cuando entra por SSH sin ejecutar un
# comando git. git-shell ejecuta este script desde
# ~/git-shell-commands/no-interactive-login.

[ -r /etc/nube/nube.conf ] && . /etc/nube/nube.conf

DOMAIN="${NUBE_BASE_DOMAIN:-}"
HOST="$(hostname -f 2>/dev/null || hostname)"

echo -e "Hola \e[1m$USER\e[0m, te conectaste correctamente."
echo ""
echo "Este servidor no ofrece shell interactivo: solo acepta git push/pull."
echo "Para publicar una app, ejecuta en tu maquina:"
echo ""
echo -e "  git remote add prod $USER@$HOST:git/\e[33;1mnombre-de-tu-app\e[0m"
echo -e "  git push prod main"
echo ""
echo "Para aplicar la configuracion del servidor (nginx, fail2ban):"
echo -e "  git push server main     \e[2m# remoto del repositorio del servidor\e[0m"
echo ""
[ -n "$DOMAIN" ] && echo -e "Apps en \e[34mhttps://<app>.$DOMAIN\e[0m"
