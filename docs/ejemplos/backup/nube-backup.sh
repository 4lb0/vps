#!/bin/bash
#
# Backup diario para un servidor Nube.
#
# Guarda:
#   - dump de todas las bases de datos
#   - sitios de /home/*/www
#   - configuracion (/etc/nube, /etc/nginx)
#
# Pensado para correr como root desde cron:
#   0 4 * * * /opt/nube/docs/ejemplos/backup/nube-backup.sh >> /var/log/nube-backup.log 2>&1
#
# Opcional: subir a un destino remoto con rclone (ver README).
#
# Credenciales de MySQL: usa /root/.my.cnf para no poner la password en la
# linea de comandos:
#   [client]
#   user=backup
#   password=...

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/nube}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
STAMP="$(date +%F-%H%M)"
WORK_DIR="$BACKUP_DIR/$STAMP"

[ "$(id -u)" -eq 0 ] || { echo "ejecutar como root" >&2; exit 1; }

mkdir -p "$WORK_DIR"

echo "==> Dump de bases de datos"
if command -v mysqldump >/dev/null 2>&1; then
    mysqldump --single-transaction --quick --routines --events \
        --all-databases | gzip > "$WORK_DIR/databases.sql.gz"
    echo "    $WORK_DIR/databases.sql.gz"
else
    echo "    mysqldump no encontrado, se omite"
fi

echo "==> Sitios"
if [ -d /home ]; then
    tar czf "$WORK_DIR/sites.tar.gz" \
        --exclude='home/*/nube-deploy.log' \
        --exclude='home/*/www/*/storage/framework/cache/*' \
        --exclude='home/*/www/*/node_modules' \
        -C / home 2>/dev/null || true
    echo "    $WORK_DIR/sites.tar.gz"
fi

echo "==> Configuracion"
tar czf "$WORK_DIR/config.tar.gz" \
    /etc/nube /etc/nginx /etc/ssh/sshd_config /etc/ssh/sshd_config.d \
    /etc/fail2ban 2>/dev/null || true
echo "    $WORK_DIR/config.tar.gz"

echo "==> Limpieza de backups mayores a $RETENTION_DAYS dias"
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime "+$RETENTION_DAYS" -exec rm -rf {} +

echo "==> Backup listo en $WORK_DIR"
du -sh "$WORK_DIR"
