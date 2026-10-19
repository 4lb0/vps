#!/bin/bash
#
# .nube/deploy para una app Node.
# Copialo a tu repo como .nube/deploy y hacelo ejecutable:
#   mkdir -p .nube && cp node-deploy.sh .nube/deploy && chmod +x .nube/deploy
#
# El hook de Nube lo ejecuta al final del deploy con la cwd en el proyecto
# y las variables NUBE_PATH, NUBE_URL, NUBE_DOMAIN, NUBE_REFS.

set -euo pipefail

echo "Instalando dependencias de Node..."
# El hook ya hace npm ci, el build y la recarga de PM2. Este script solo es
# necesario si querés controlar esos pasos a mano.
npm ci --no-audit --no-fund

echo "Compilando (si hay script build)..."
npm run build --if-present

echo "Reiniciando con PM2..."
pm2 startOrReload ecosystem.config.js --update-env
pm2 save
