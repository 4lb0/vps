# 08 · Solución de problemas

Diagnóstico por síntoma. Regla general: **primero los logs**, después la
teoría.

```bash
sudo tail -50 /var/log/nginx/error.log
sudo journalctl -u php8.3-fpm -n 50
sudo journalctl -u nginx -n 50
tail -50 /home/<usuario>/nube-deploy.log
```

## SSH y git push

### `Permission denied (publickey)`

- Tu clave no está en `~usuario/.ssh/authorized_keys`.

  ```bash
  ssh -v nube@nube.example.com     # mirá qué clave ofrece
  sudo cat /home/nube/.ssh/authorized_keys
  ```

- Permisos incorrectos (sshd los rechaza):

  ```bash
  sudo chmod 700 /home/nube/.ssh
  sudo chmod 600 /home/nube/.ssh/authorized_keys
  sudo chown -R nube:nube /home/nube/.ssh
  ```

- Estás usando `root` y `PermitRootLogin no` (correcto): entrá como tu
  usuario admin.
- `AllowGroups` no incluye a tu usuario:

  ```bash
  getent group nube sudo
  groups nube
  ```

### `Host key verification failed`

El servidor reinstaló su host key (o cambiaste de VPS). Borrá la entrada vieja:

```bash
ssh-keygen -R nube.example.com
```

### `fatal: '<app>' does not appear to be a git repository`

El repositorio bare no existe o el nombre no coincide:

```bash
sudo ls /home/nube/git/
```

Creá el repo con:

```bash
sudo runuser -u nube -- nr <app> <dominio> | sudo mysql
```

### El push queda colgado después de `remote:`

Un paso del hook está esperando input (por ejemplo `migrate` pidiendo
confirmación). Revisá el log y agregá `--no-interaction`/`--force` en tu hook
propio.

### `remote: nube: error: ...` con el deploy a medias

Cada mensaje de error indica el problema. Los más comunes:

| Mensaje | Causa |
| --- | --- |
| `no existe el directorio web /var/www/...` | El symlink no existe: corré `nd`/`ns` o `nr` |
| `no se pudo crear /var/www/...` | `/var/www` sin permiso de grupo: ver [01](01-preparar-ubuntu.md#12-directorios-y-permisos) |
| `composer: command not found` | Composer no instalado globalmente |
| `hay package.json pero npm no esta instalado` | Falta Node.js en el servidor (ver [01](01-preparar-ubuntu.md#10-nodejs-y-python-opcional)) |
| `hay requirements.txt o pyproject.toml pero python3 no esta instalado` | Falta Python 3 en el servidor |
| `no se pudo crear .venv` | Falta `python3-venv`: `sudo apt install python3-venv` |
| `no se pudo descifrar .../secrets.gpg` | Clave GPG o `secrets.gpg` de otro usuario |
| `Laravel necesita un .env` | Falta `.env.example` en el repo |
| `faltan credenciales de DB` | `secrets.gpg` vacío o corrupto |

## Configuración del servidor (`git push server main`)

### `nube: error: no se pudo aplicar la configuracion`

El push no cambia nada: Nube restaura la configuración anterior de nginx.
Corré en el servidor para ver el error completo:

```bash
sudo nube-apply-config
```

Casi siempre es un `syntax error` en algún archivo de
[`nginx/`](../nginx/), un `fastcgi_pass` con una versión de PHP que no existe
(`NUBE_PHP_VERSION`), o un certificado que no se puede leer. Corregilo en el
repositorio y volvé a hacer push.

### `sudo: a password is required` en el hook

Falta el sudoers acotado. Volvé a correr:

```bash
cd /opt/nube && sudo ./bootstrap.sh
```

### `nube: error: no existe el repositorio del servidor`

El repositorio y su hook los crea `bootstrap.sh`: corré `sudo ./bootstrap.sh`
en el clon del servidor.

## Web (nginx y PHP)

### 502 Bad Gateway

PHP-FPM no está escuchando en el socket que nginx espera.

```bash
ls -l /run/php/
sudo systemctl status php8.3-fpm
sudo nginx -T | grep fastcgi_pass
```

Si el socket es `php8.3-fpm.sock` pero nginx apunta a `php8.1-fpm.sock`,
Editá el include de nginx o creá un symlink:

```bash
sudo ln -s /run/php/php8.3-fpm.sock /run/php/php-fpm.sock
```

### 403 Forbidden

- Permisos: nginx (usuario `www-data`) no puede leer el archivo o atravesar
  `/home/<usuario>`.

  ```bash
  namei -l /home/nube/www/blog.example.com/public/index.php
  ```

  Los directorios deben tener `x` para `www-data`; el home debe ser
  `nube:www-data 750`.
- Nginx bloqueando la ruta por `nube-block-scanners` (`.env`, `.git`,
  `wp-admin`, `phpmyadmin`).
- `autoindex off` y no hay `index.html`/`index.php`.

### 404 en todas las rutas (Laravel)

Falta el `try_files` hacia `index.php` o el `root` apunta mal:

```bash
sudo nginx -T | grep -A2 "root "
curl -I https://blog.example.com/index.php
```

### 500 con `Error` genérico

Mirá el log de la app y el de PHP-FPM:

```bash
tail -100 /home/nube/www/blog.example.com/storage/logs/laravel.log
sudo journalctl -u php8.3-fpm -n 50
```

Causas típicas: `APP_KEY` faltante, permisos de `storage/`, migraciones sin
correr, `.env` malformado.

### El sitio muestra la página por defecto

El push llegó a un directorio distinto del que nginx sirve:

```bash
ls -l /var/www/blog.example.com
# debe ser un symlink a /home/nube/www/blog.example.com
readlink -f /var/www/blog.example.com
```

### Cambios que no aparecen

- El navegador tiene cache: probá en incógnito o `Ctrl+Shift+R`.
- El push fue a otra rama: el hook solo despliega la rama pusheada.
- Faltó `git push`: revisá `git status`.

## Certificados y TLS

### `SSL_ERROR_RX_RECORD_TOO_LONG`

Estás entrando por HTTP a un puerto que habla HTTPS (o al revés). Usá
`https://` y verificá el redirect.

### `NET::ERR_CERT_COMMON_NAME_INVALID`

El certificado no cubre ese nombre:

- El wildcard cubre **un** nivel (`*.nube.example.com` no cubre
  `a.b.nube.example.com`).
- El dominio propio no tiene certificado emitido: corré `nd` de nuevo.
- El `server_name` de nginx no coincide con el dominio.

```bash
echo | openssl s_client -connect nube.example.com:443 -servername tu-dominio 2>/dev/null \
  | openssl x509 -noout -subject -ext subjectAltName
```

### `nginx: cannot load certificate`

El archivo no existe o es ilegible:

```bash
ls -l /etc/nginx/ssl/nube.crt /etc/nginx/ssl/nube.key
sudo -u www-data head -1 /etc/nginx/ssl/nube.crt   # nginx master lee como root
```

Reinstalá con `acme.sh --install-cert` (ver [02](02-dominio-y-dns.md)).

### El challenge de acme.sh falla

```bash
# ¿Resuelve el dominio al VPS?
dig +short tu-dominio

# ¿Nginx sirve el challenge?
mkdir -p /var/www/acme/.well-known/acme-challenge
echo ok | sudo tee /var/www/acme/.well-known/acme-challenge/test
curl -i http://tu-dominio/.well-known/acme-challenge/test
```

Si la última respuesta no es `ok`, revisá `nube-acme.conf` y que el server
HTTP no redirija *antes* del `location` del challenge.

## Base de datos

### `Access denied for user ...`

El `.env` tiene credenciales viejas. Hacé un push para que el hook las
actualice, o revisá:

```bash
sudo runuser -u nube -- env HOME=/home/nube gpg -d /home/nube/secrets.gpg
sudo mysql -e "SELECT user, host FROM mysql.user WHERE user LIKE 'nube%';"
```

### `Can't connect to MySQL server`

```bash
sudo systemctl status mariadb   # o mysql
sudo ss -tlnp | grep 3306
df -h                            # disco lleno
```

### `Specified key was too long`

MySQL viejo e índices `utf8mb4`. El hook aplica un workaround de 191
caracteres; si igual falla, configurá el charset en las migraciones.

### Las migraciones no corren

- `NUBE_SKIP_MIGRATIONS=1` no está seteado (es una variable del servidor).
- El usuario no existe en el `.env`.
- Revisá `tail -50 ~/nube-deploy.log`.

## Sistema

### Disco lleno

```bash
df -h
sudo du -xh / 2>/dev/null | sort -h | tail -20
```

Limpieza típica:

```bash
sudo journalctl --vacuum-time=7d
sudo apt clean
sudo npm cache clean --force
sudo find /var/log -name '*.gz' -delete
du -sh /home/*/www/*/node_modules
```

### fail2ban me bloqueó

Entrá por la consola del proveedor y:

```bash
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip TU-IP
```

Agregá tu IP a `ignoreip` para que no vuelva a pasar.

### `systemctl` no arranca un servicio

```bash
sudo systemctl status <servicio>
sudo journalctl -u <servicio> -n 100 --no-pager
sudo nginx -t
sudo php-fpm8.3 -t
```

### Alta carga

```bash
uptime
top -o %CPU
vmstat 1
sudo tail -100 /var/log/nginx/access.log | awk '{print $1}' | sort | uniq -c | sort -rn | head
```

Un bot haciendo scraping puede saturar; revisá fail2ban y `limit_req`.

## Comandos de diagnóstico rápido

```bash
# Todo el estado de una vez
sudo nginx -t && echo "nginx ok"
systemctl is-active nginx php8.3-fpm mariadb fail2ban
sudo ss -tlnp | grep -E ':(80|443|3306)'
df -h / && free -h
sudo tail -5 /var/log/nginx/error.log
sudo fail2ban-client status | head
```

Volver al [índice](README.md).
