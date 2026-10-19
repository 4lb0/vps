#!/bin/bash
#
# .nube/deploy para Laravel.
# Copialo a tu repo como .nube/deploy y hacelo ejecutable.
#
# El hook de Nube ya hace composer install, caches y migraciones. Este script
# agrega pasos propios: storage:link, reinicio de workers, etc.

set -euo pipefail

echo "Enlazando storage..."
php artisan storage:link --no-interaction || true

echo "Reiniciando workers de cola..."
php artisan queue:restart || true

echo "Ejecutando tareas post-deploy..."
# php artisan mi:comando
