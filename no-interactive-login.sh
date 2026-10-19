#!/bin/bash
#
# Mensaje que ve un usuario cuando entra por SSH sin ejecutar un comando git.
# git-shell ejecuta este script desde ~/git-shell-commands/no-interactive-login.

[ -r /etc/nube/nube.conf ] && . /etc/nube/nube.conf

DOMAIN="${NUBE_BASE_DOMAIN:-nube.pragmore.com}"

echo -e "Hola \e[1m$USER\e[0m, te conectaste correctamente."
echo ""
echo "Este servidor no ofrece shell interactivo: solo acepta git push/pull."
echo "Para configurar el deploy, ejecuta en tu maquina:"
echo ""
echo -e "  git remote add prod $USER@$DOMAIN:git/\e[33;1mnombre-de-tu-app\e[0m"
echo -e "  git push prod main"
echo ""
echo -e "Si necesitas ayuda: \e[34;4mhttps://$DOMAIN/ayuda\e[0m"
