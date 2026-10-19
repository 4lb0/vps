#!/bin/bash
#
# .nube/deploy para una app Python.
# Copialo a tu repo como .nube/deploy y hacelo ejecutable:
#   mkdir -p .nube && cp python-deploy.sh .nube/deploy && chmod +x .nube/deploy
#
# El hook de Nube ya crea .venv e instala requirements.txt o pyproject.toml.
# Este script solo reinicia el proceso. Necesita una regla de sudoers para
# systemctl restart del servicio (o corré el proceso con PM2 y usá
# "pm2 restart <nombre>").

set -euo pipefail

echo "Reiniciando la app..."
sudo systemctl restart blog
