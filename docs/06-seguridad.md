# 06 · Seguridad

Un VPS expuesto a Internet recibe escaneos y ataques automatizados desde el
primer minuto. Esta guía cubre lo mínimo indispensable y cómo endurecer cada
componente de Nube.

> **Regla de oro:** hacé los cambios de SSH desde una segunda sesión abierta.
> Si algo sale mal, todavía podés entrar por la que ya está conectada o por la
> consola del proveedor.

## 0. Modelo de amenaza

| Riesgo | Mitigación |
| --- | --- |
| Fuerza bruta SSH | Solo claves, `fail2ban`, `AllowGroups` |
| Robo de credenciales de apps | Secretos cifrados, `.env` fuera de git, permisos |
| Escaneo de rutas (`.env`, `.git`, phpMyAdmin…) | `prevent-attacks`, headers, fail2ban |
| Aislamiento entre clientes | PHP-FPM por usuario (opcional), MySQL por app |
| Dependencias vulnerables | Actualizaciones, `composer audit`, `npm audit` |
| Kernel/servicios desactualizados | `unattended-upgrades` |
| Fuga de datos | Backups cifrados, rotación de claves |

Nube **no** es un hosting multi-tenant endurecido. Si vas a alojar clientes
distintos, además de esta guía leé la sección
[PHP-FPM por usuario](#php-fpm-por-usuario).

## 1. Checklist priorizada

1. [ ] Solo autenticación por clave SSH y root deshabilitado.
2. [ ] `fail2ban` activo con SSH, nginx y reincidentes.
3. [ ] UFW permitiendo solo 22, 80 y 443.
4. [ ] Actualizaciones automáticas de seguridad.
5. [ ] MySQL escuchando solo en `127.0.0.1`.
6. [ ] `/etc/nube/nube.conf` y secretos sin permisos de más.
7. [ ] Headers, rate limit y TLS en nginx.
8. [ ] Backups probados (ver [07](07-operacion-y-backups.md)).
9. [ ] Si hay terceros: pool de PHP-FPM por usuario.
10. [ ] Monitoreo de logs y auditoría ocasional.

## 2. SSH

Editá (o creá) `/etc/ssh/sshd_config.d/99-nube.conf`:

```sshconfig
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no

# Solo admins (sudo) y usuarios de deploy (nube) pueden conectarse.
AllowGroups sudo nube

MaxAuthTries 3
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2

X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
```

`install.sh` crea el grupo `nube` y `add-user.sh` agrega cada usuario de
deploy a ese grupo. Si creaste usuarios a mano:

```bash
sudo groupadd -f nube
sudo usermod -aG nube juan
```

Validá **antes** de reiniciar:

```bash
sudo sshd -t
sudo systemctl restart ssh
```

Comprobaciones:

```bash
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication|allowgroups'
ssh -o PreferredAuthentications=password root@tu-servidor   # debe fallar
last -a | head
```

### Buenas prácticas de claves

- Usá **ed25519** o RSA de 4096 bits.
- Protegé tu clave privada con passphrase y usá `ssh-agent`.
- Una clave por dispositivo; borrá las viejas de `authorized_keys`.
- No compartas `~/.ssh/id_ed25519` de los usuarios de deploy: esa clave es
  para que **ellos** clonen repos privados, no para entrar.

### Limitar qué puede hacer una clave

Podés restringir una clave en `authorized_keys`:

```text
from="203.0.113.0/24",no-port-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA... juan@casa
```

## 3. fail2ban

```bash
sudo apt install -y fail2ban
sudo cp fail2ban/jail.local /etc/fail2ban/jail.local
sudo cp fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/
sudo systemctl enable --now fail2ban
```

Antes de reiniciar, editá `ignoreip` con tu IP de administración:

```ini
ignoreip = 127.0.0.1/8 ::1 203.0.113.10
```

Estado y pruebas:

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client status nginx-nube-scan
sudo tail -f /var/log/fail2ban.log
```

Desbanear:

```bash
sudo fail2ban-client set sshd unbanip 203.0.113.50
```

### Cómo se conecta con nginx

El jail `nginx-nube-scan` lee `/var/log/nginx/access.log` con el formato
definido en `nginx.conf`:

```text
$host $remote_addr - $remote_user [$time_local] "$request" ...
```

Si cambiás `log_format`, actualizá también
[`fail2ban/filter.d/nginx-nube-scan.conf`](../fail2ban/filter.d/nginx-nube-scan.conf).

El jail `nginx-req-limit` requiere que nginx registre los rechazos de
`limit_req` en el error log, algo que ya hace. Verificá que el archivo de
zonas y el snippet de seguridad estén incluidos.

### Cloudflare

Si usás Cloudflare con proxy, nginx ve la IP de Cloudflare y fail2ban la
banearía. Configurá `real_ip` como se explica en
[02 · Dominio y DNS](02-dominio-y-dns.md#6-cloudflare-proxy-y-ip-real).
Comprobá con:

```bash
sudo fail2ban-client status nginx-nube-scan
# las IPs baneadas deben ser de visitantes, no de Cloudflare
```

## 4. Firewall (UFW)

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw logging on
sudo ufw enable
sudo ufw status verbose
```

Notas:

- fail2ban agrega sus propias reglas y convive con UFW.
- Si cambiás el puerto de SSH, actualizá la regla **antes** de reiniciar sshd.
- No abras MySQL (`3306`) ni Redis: deben escuchar solo en localhost.
- Con IPv6, UFW también aplica; verificá `sudo ufw status` muestra `(v6)`.

## 5. Actualizaciones

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Configuración recomendada en
`/etc/apt/apt.conf.d/50unattended-upgrades`:

```conf
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
```

Comprobá:

```bash
sudo unattended-upgrade --dry-run --debug
systemctl status unattended-upgrades
```

Los parches de kernel requieren reinicio. Revisá `/var/run/reboot-required`
con `cat` y reiniciá en una ventana de mantenimiento. Para no reiniciar,
considerá Ubuntu Livepatch (gratis para uso personal).

Actualizá también las dependencias de cada app:

```bash
cd /home/juan/www/blog.example.com
sudo runuser -u juan -- composer audit
sudo runuser -u juan -- npm audit
```

## 6. Endurecer nginx

La configuración de ejemplo
([`docs/ejemplos/nginx/`](ejemplos/nginx/)) ya incluye:

- `server_tokens off` (no expone la versión);
- headers `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`,
  `Permissions-Policy`;
- `limit_req` y `limit_conn` por IP;
- TLS 1.2/1.3 con ciphers modernos;
- bloqueo de archivos ocultos y de extensiones peligrosas
  (`.env`, `.git`, `.sql`, `.bak`, configs);
- `client_max_body_size` y timeouts acotados.

Además:

```nginx
# No aceptar metodos que no uses
if ($request_method !~ ^(GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS)$) {
    return 405;
}
```

Con Laravel o frameworks con front controller, restringí PHP a `index.php`
para evitar ejecutar subidas:

```nginx
location ~ \.php$ {
    try_files $uri =404;
    include /etc/nginx/fastcgi.conf;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
}

# Nada de PHP dentro de uploads
location ~* ^/storage/.*\.php$ {
    deny all;
}
```

### HSTS

Activalo solo cuando **todo** el dominio funcione por HTTPS:

```nginx
add_header Strict-Transport-Security "max-age=31536000" always;
```

Con subdominios que todavía no tienen TLS, agregar `includeSubDomains` puede
dejarlos inaccesibles.

### Verificar TLS

```bash
openssl s_client -connect tu-dominio:443 -servername tu-dominio </dev/null \
  | openssl x509 -noout -subject -dates
curl -sSI https://tu-dominio | grep -i strict-transport
```

O usá el test externo de [SSL Labs](https://www.ssllabs.com/ssltest/).

## 7. PHP-FPM por usuario

**Este es el punto más importante para alojar terceros.** Por defecto hay un
solo pool (`www-data`) para todos los sitios: un bug en una app puede leer
archivos de otra que sean legibles por grupo.

Podés crear un pool por usuario. Ejemplo para `juan` en
`/etc/php/8.3/fpm/pool.d/juan.conf`:

```ini
[juan]
user = juan
group = juan

listen = /run/php/nube-juan.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = 5
pm.process_idle_timeout = 10s
pm.max_requests = 500

php_admin_value[open_basedir] = /home/juan:/tmp
php_admin_value[session.save_path] = /home/juan/tmp
php_admin_value[upload_tmp_dir] = /home/juan/tmp
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen

php_admin_flag[log_errors] = on
php_admin_value[error_log] = /home/juan/php-error.log
```

Creá el directorio de sesiones y recargá:

```bash
sudo install -d -o juan -g juan -m 0700 /home/juan/tmp
sudo systemctl reload php8.3-fpm
ls -l /run/php/nube-juan.sock
```

En el `server` de nginx de ese usuario:

```nginx
fastcgi_pass unix:/run/php/nube-juan.sock;
```

Precauciones:

- `open_basedir` puede romper apps que leen fuera de su home. Probá antes de
  aplicarlo a producción.
- `disable_functions` puede romper Composer/artisan si se ejecutan vía web (no
  debería) o librerías que usan `proc_open`. Ajustá la lista.
- El pool debe correr como el usuario dueño para que `storage/` y los archivos
  tengan los permisos correctos. Alternativamente, dejá `www-data` pero
  confiá en los permisos de grupo.
- Hay un ejemplo listo en
  [`docs/ejemplos/php-fpm/juan.conf`](ejemplos/php-fpm/juan.conf).

## 8. MySQL / MariaDB

Verificá que escuche solo en localhost:

```bash
sudo ss -tlnp | grep 3306
```

En `/etc/mysql/mariadb.conf.d/50-server.cnf` (o
`/etc/mysql/mysql.conf.d/mysqld.cnf`):

```ini
bind-address = 127.0.0.1
local_infile = 0
symbolic-links = 0
```

Buenas prácticas:

- Ejecutá `mariadb-secure-installation` / `mysql_secure_installation`.
- Cada app tiene su usuario y su base (Nube lo hace).
- No uses `GRANT ALL ON *.*` para usuarios de app.
- Para backups, creá un usuario de solo lectura:

```sql
CREATE USER 'backup'@'127.0.0.1' IDENTIFIED BY '...';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup'@'127.0.0.1';
```

- El `root` de MySQL debe autenticar por socket (`auth_socket`), no con
  contraseña remota.

## 9. Secretos y permisos

| Archivo | Permisos | Nota |
| --- | --- | --- |
| `/etc/nube/nube.conf` | `0644` | Sin secretos |
| `/home/<user>/secrets.gpg` | `0600` | Credenciales cifradas |
| `/home/<user>/.env` | `0600` | Secretos de la app |
| `/home/<user>/.ssh` | `0700` | |
| `/home/<user>/.ssh/authorized_keys` | `0600` | |
| `/etc/nginx/ssl` | `2770 root:www-data` | Certificados |

Sobre GPG sin passphrase: la clave se genera sin contraseña porque el hook de
deploy la usa de forma no interactiva. **No protege contra root**; sirve para
que las credenciales no queden en texto plano. Si querés más seguridad, usá
un gestor de secretos (Vault, SOPS con KMS) y adaptá el hook.

Reglas:

- Nunca commitees `.env`, `secrets.gpg` ni claves.
- No pongas secretos en la línea de comandos: quedan en `history` y en
  `ps`. Usá `mysql` por stdin o variables de entorno.
- Rotalas si se filtraron (ver
  [04 · Usuarios y apps](04-usuarios-y-aplicaciones.md#10-cambiar-credenciales-de-base)).
- Revisá `~/.bash_history`, `/root/.bash_history` y los logs de auditoría
  como parte de una revisión.

## 10. git-shell y usuarios

Los usuarios de deploy:

- tienen `git-shell` como shell: no pueden ejecutar comandos arbitrarios;
- ven el mensaje de `no-interactive-login` si intentan entrar;
- no deben pertenecer a `sudo`.

Verificaciones:

```bash
getent passwd juan        # /usr/bin/git-shell
sudo -l -U juan           # no debería tener sudo
sudo grep -r nopasswd /etc/sudoers /etc/sudoers.d/
```

Si un usuario necesita correr tareas (cron, workers), hacelo con un servicio
systemd con `User=juan` o con `cron` propio, no dándole shell.

### sudoers acotado (opcional)

Si querés que un hook propio pueda recargar nginx sin dar sudo completo:

```bash
sudo visudo -f /etc/sudoers.d/nube-reload
```

```sudoers
juan ALL=(root) NOPASSWD: /bin/systemctl reload nginx
```

## 11. Seguridad de la aplicación

Del lado de cada proyecto:

- `APP_DEBUG=false` y `APP_ENV=production` en producción.
- Actualizá framework y dependencias con regularidad.
- Validá y escapá toda entrada; no confíes en el cliente.
- No guardes uploads con extensión ejecutable dentro de `public/`.
- Usá HTTPS en todas las URLs; en Laravel, `URL::forceScheme('https')` detrás
  del proxy.
- Revisá logs de errores sin exponerlos (`storage/logs` fuera del webroot).
- No expongas `.git`: nginx ya lo bloquea en la config de ejemplo.
- Correlo con `APP_KEY` única y rotala si se filtró.

## 12. Monitoreo y detección

```bash
# Intentos de login fallidos
sudo grep -c "Failed password" /var/log/auth.log
sudo lastb | head

# Quién está conectado
who
ss -tupn

# Servicios y puertos
systemctl --failed
sudo ss -tlnp

# Logs recientes de fail2ban
sudo grep "Ban " /var/log/fail2ban.log | tail

# Auditoría completa (opcional)
sudo apt install -y lynis
sudo lynis audit system
```

Opcionales:

- **CrowdSec**: alternativa/complemento a fail2ban con listas comunitarias.
- **auditd**: auditoría de syscalls; útil para forense, verboso para el día a
  día.
- **Uptime Kuma / healthchecks.io**: avisos si el sitio se cae.
- **AIDE**: detección de cambios en archivos del sistema.

## 13. Respuesta a incidentes

Si sospechás que el servidor fue comprometido:

1. **Aislá sin apagar**: cortá el tráfico (`sudo ufw default deny incoming`)
   pero dejá el SSH abierto desde tu IP, y sacá un snapshot en el proveedor.
2. **Preservá evidencia**: logs (`/var/log`), `last`, `ps auxf`, conexiones
   (`ss -tupn`), cron (`crontab -l`, `/etc/cron*`), servicios.
3. **Rotá credenciales**: claves SSH, bases de datos, tokens de API, secretos
   de apps.
4. **Identificá el vector**: revisá webshells en `public/`, usuarios nuevos,
   tareas cron, claves en `authorized_keys`.
5. **Reconstruí**: si hubo acceso root, lo más seguro es reinstalar el VPS
   desde cero, restaurar backups y redeployar.
6. **Documentá** qué pasó y qué cambiaste para que no vuelva a pasar.

## 14. Backups

Un backup que nunca se restauró no es un backup. La estrategia y el script de
ejemplo están en
[07 · Operación y backups](07-operacion-y-backups.md).

## Checklist final

- [ ] `PasswordAuthentication no` y `PermitRootLogin no`.
- [ ] `AllowGroups sudo nube` y usuarios de deploy sin sudo.
- [ ] fail2ban activo con `sshd`, `recidive`, `nginx-nube-scan`.
- [ ] UFW activo con 22/80/443.
- [ ] `unattended-upgrades` instalado.
- [ ] MySQL en `127.0.0.1` y `local_infile=0`.
- [ ] Headers, rate limit y TLS probados con SSL Labs (A o mejor).
- [ ] `.env` y `secrets.gpg` con permisos correctos.
- [ ] Backups automáticos + una restauración de prueba.
- [ ] Pool de PHP-FPM por usuario si hay terceros.

Siguiente: [07 · Operación y backups](07-operacion-y-backups.md).
