# 07 · Operación y backups

Tareas para mantener el servidor sano después de la puesta en marcha.

## 1. Rutina

### Todos los días (5 minutos)

```bash
# ¿Algo fallo?
systemctl --failed
sudo fail2ban-client status | head

# ¿Disco y memoria?
df -h
free -h

# ¿Deploys de ayer?
sudo grep -h "deploy" /home/*/nube-deploy.log 2>/dev/null | tail
```

### Todas las semanas

```bash
# ¿Hay reinicio pendiente por kernel?
cat /var/run/reboot-required 2>/dev/null || echo "sin reinicio pendiente"

# Bans recientes
sudo grep "Ban " /var/log/fail2ban.log | tail -20

# Certificados por vencer
for d in /etc/nginx/ssl/*/; do
    [ -f "$d/fullchain.pem" ] || continue
    echo -n "$d: "
    openssl x509 -enddate -noout -in "$d/fullchain.pem"
done

# Espacio de backups
du -sh /var/backups/nube

# Logs grandes
sudo du -sh /var/log/nginx/*.log
```

### Todos los meses

- Actualizar el sistema: `sudo apt update && sudo apt upgrade`.
- Revisar dependencias de las apps (`composer audit`, `npm audit`).
- Probar una restauración de backup en un entorno de prueba.
- Revisar usuarios y claves SSH:

  ```bash
  getent group nube
  for u in $(getent group nube | cut -d: -f4 | tr ',' ' '); do
      echo "== $u"; cat /home/$u/.ssh/authorized_keys 2>/dev/null
  done
  ```
- Correr `lynis audit system` (opcional).

## 2. Servicios

| Servicio | Comando |
| --- | --- |
| nginx | `sudo systemctl reload nginx` / `restart` |
| PHP-FPM | `sudo systemctl reload php8.3-fpm` |
| MySQL | `sudo systemctl status mariadb` (o `mysql`) |
| fail2ban | `sudo systemctl status fail2ban` |
| PM2 de un usuario | `sudo runuser -u juan -- env HOME=/home/juan pm2 status` |

Recargar es más suave que reiniciar: nginx y PHP-FPM terminan las conexiones
en curso antes de aplicar el cambio.

## 3. Logs

| Log | Contenido |
| --- | --- |
| `/var/log/nginx/access.log` | Cada request (formato `nube`) |
| `/var/log/nginx/error.log` | Errores de nginx y de PHP-FPM |
| `/var/log/auth.log` | Logins SSH |
| `/var/log/fail2ban.log` | Bans y unbans |
| `/home/<user>/nube-deploy.log` | Salida de cada deploy |
| `/home/<user>/www/<dominio>/storage/logs/` | Logs de Laravel |
| `journalctl -u php8.3-fpm` | Errores de PHP-FPM |

Comandos útiles:

```bash
# Los 20 errores de nginx más recientes
sudo tail -20 /var/log/nginx/error.log

# Requests con más tiempo de respuesta
sudo awk '{print $NF, $0}' /var/log/nginx/access.log | sort -rn | head

# Requests 5xx de la última hora
sudo grep '" 5' /var/log/nginx/access.log | tail

# Logs en vivo
sudo journalctl -u php8.3-fpm -f
sudo journalctl -u nginx -f
```

### Rotación

Ubuntu ya rota los logs de nginx con `logrotate`. Si tus logs de deploy o de
app crecen mucho, agregá `/etc/logrotate.d/nube`:

```conf
/home/*/nube-deploy.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    copytruncate
}
```

## 4. Actualizaciones

```bash
# Sistema
sudo apt update
sudo apt list --upgradable
sudo apt upgrade
sudo apt autoremove

# PHP (si agregaste un PPA)
sudo apt update && sudo apt upgrade php8.3-*

# Nube
cd /opt/nube && sudo git pull && sudo ./install.sh

# Certificados (lo hace acme.sh por cron)
sudo /root/.acme.sh/acme.sh --list
sudo /root/.acme.sh/acme.sh --cron
```

Después de actualizar:

```bash
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl reload php8.3-fpm
```

## 5. Capacidad y rendimiento

Señales de que el VPS se quedó corto:

- `free -h` con swap casi lleno.
- `load average` (en `uptime`) mayor a la cantidad de vCPU de forma sostenida.
- `iowait` alto en `top`/`vmstat`.
- PHP-FPM con `max_children` alcanzado (`sudo systemctl status php8.3-fpm` o
  el status de FPM si está habilitado).

Ajustes:

- Bajar `pm.max_children` o usar `pm = ondemand` (menos RAM ociosa).
- Cachear en la app (config, rutas, vistas, objetos).
- Mover backups offsite y limpiar local.
- Separar MySQL a otro VPS si compite por RAM.
- Escalar verticalmente (más RAM/CPU) antes de pensar en varios servidores.

## 6. Cuando algo se cae

1. Revisar `systemctl --failed` y `journalctl -xe`.
2. Verificar disco: `df -h` (un disco lleno rompe MySQL y PHP).
3. Verificar servicios: nginx, PHP-FPM, MySQL, fail2ban.
4. Revisar el log de deploy de la última app desplegada.
5. Si un sitio solo falla, `nginx -t` y los logs de la app.
6. Si todo falla, la guía de [08 · Solución de problemas](08-solucion-de-problemas.md).

## 7. Programar tareas

- **Cron del sistema**: `/etc/cron.d/nube` para tareas de root (backups,
  healthchecks).
- **Cron por usuario**: `sudo runuser -u juan -- crontab -e`.
- **systemd timers**: más robustos que cron para tareas que deben correr una
  sola vez (`OnCalendar`, `Persistent=true`).
- **Workers de Laravel**: `queue:work` como servicio systemd con `User=juan`,
  no en cron.

Ejemplo de timer + servicio systemd:

```ini
# /etc/systemd/system/nube-backup.service
[Unit]
Description=Backup de Nube

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nube-backup
```

```ini
# /etc/systemd/system/nube-backup.timer
[Unit]
Description=Backup diario de Nube

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl enable --now nube-backup.timer
systemctl list-timers
```

## 8. Monitoreo externo

Un monitor que corra **fuera** del VPS avisa cuando el servidor está caído:

- [healthchecks.io](https://healthchecks.io): el cron hace un ping; si no
  llega, te avisa.
- Uptime Kuma (autoalojado o en otro servidor).
- UptimeRobot, Better Stack, etc.

Ejemplo con healthchecks:

```bash
curl -fsS --retry 3 https://hc-ping.com/TU-UUID > /dev/null
```

## Checklist

- [ ] Backups automáticos configurados y con copia offsite.
- [ ] Restauración probada.
- [ ] Logs revisados periódicamente.
- [ ] Actualizaciones automáticas de seguridad activas.
- [ ] Monitor externo avisando si el sitio se cae.
- [ ] Runbook propio actualizado con tus dominios y usuarios.

Siguiente: [08 · Solución de problemas](08-solucion-de-problemas.md).
