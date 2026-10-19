# Comandos y variables

Referencia de la interfaz de Nube.

Los comandos se instalan en `/usr/local/bin` y se invocan siempre por su
nombre completo: no hay alias cortos.

## Comandos

### `bootstrap.sh [opciones]`

Requiere **root** y se corre **una vez**, en el clon del repositorio.

Aplica la configuración, crea el usuario de deploy, crea el repositorio del
servidor (`~/git/nube.git`) con su hook y habilita el sudoers acotado.
Opciones: `--base-domain`, `--user`, `--email`, `--php`, `--ssh-key`,
`--ssh-key-file`. Ver
[03 · Instalar Nube](../03-instalar-nube.md#2-preparar-el-servidor-con-bootstrapsh).

### `install.sh [directorio-origen]`

Requiere **root**. Sin argumentos usa el directorio del script.

Copia los scripts a `/usr/local/lib/nube`, crea los comandos, deja
`/etc/nube/nube.conf` (solo si no existe) y aplica `nginx/` y `fail2ban/` con
backup y rollback si `nginx -t` falla.

Es el comando que ejecuta `nube-apply-config` en cada push al repositorio del
servidor.

### `nube-apply-config`

Requiere **root**. Hace checkout de `$NUBE_SERVER_REF` desde
`$NUBE_SERVER_REPO` en `$NUBE_SERVER_SRC` y ejecuta el `install.sh` de esa
copia.

```bash
sudo nube-apply-config
```

### `nube-init-user [<clave-publica> | --key-file <archivo.pub>]`

Script: `init-user.sh`. Requiere **root**.

Crea el usuario `$NUBE_USER` con `git-shell`, su usuario de MySQL,
`secrets.gpg` y la clave SSH. Si el usuario ya existe, solo agrega la clave.
Detalle en
[04 · El usuario y las apps](../04-usuario-y-apps.md#2-el-usuario-de-deploy).

### `nube-add-repository <app> [<dominio>]`

Script: `add-repository.sh`. Se ejecuta **como el usuario de deploy**.

Crea/actualiza `~/git/<app>.git` y su hook, asegura el directorio web e
imprime el SQL de MySQL por stdout.

```bash
sudo runuser -u nube -- nube-add-repository blog blog.example.com | sudo mysql
```

Errores posibles: nombre o dominio inválido, permisos en `/var/www`, falta de
`secrets.gpg`.

### `nube-add-domain <dominio>`

Script: `add-domain.sh`. Como el usuario de deploy.

Crea el sitio, la página inicial y emite/instala el certificado según
`NUBE_ACME_MODE`. Ver
[04](../04-usuario-y-apps.md#4-crear-una-app-en-un-dominio-propio).

### `nube-add-subdomain <subdominio>`

Script: `add-subdomain.sh`. Como el usuario de deploy.

Crea `<subdominio>.<NUBE_BASE_DOMAIN>`. No emite certificado (lo cubre el
wildcard).

### `nube-hook-post-update <ref> <dominio> <git-dir>`

Hook interno. Lo invoca `hooks/post-update`. No se ejecuta a mano.

Variables que acepta del entorno del servidor:

| Variable | Efecto |
| --- | --- |
| `NUBE_SKIP_COMPOSER=1` | No corre `composer install` |
| `NUBE_SKIP_NPM=1` | No corre `npm ci`/`npm install` ni el build |
| `NUBE_SKIP_PYTHON=1` | No crea `.venv` ni corre `pip install` |
| `NUBE_SKIP_MIGRATIONS=1` | No corre `php artisan migrate` |
| `NUBE_SKIP_ARTISAN_CACHE=1` | No corre `config:cache`, `route:cache`, `view:cache` |

### `nube-motd`

Banner de login. Se puede instalar en `/etc/profile.d/` o `/etc/motd`.

### `test-hook.sh [ruta] [remoto] [url]`

Prueba de humo del deploy desde tu máquina.

## Variables de `/etc/nube/nube.conf`

| Variable | Default | Descripción |
| --- | --- | --- |
| `NUBE_USER` | `nube` | El único usuario de deploy |
| `NUBE_USER_MAIL` | vacío | Email de la clave GPG del usuario |
| `NUBE_BASE_DOMAIN` | `nube.example.com` | Dominio base de los subdominios |
| `NUBE_WEB_ROOT` | `/var/www` | Directorio de symlinks |
| `NUBE_WEB_GROUP` | `www-data` | Grupo con acceso a los sitios |
| `NUBE_SSH_GROUP` | `nube` | Grupo con acceso SSH |
| `NUBE_PHP_VERSION` | `8.3` | Versión de PHP (socket de nginx) |
| `NUBE_ACME_HOME` | `$HOME/.acme.sh` | acme.sh del usuario que corre `nube-add-domain` |
| `NUBE_ACME_MODE` | `webroot` | `webroot`, `stateless` o `none` |
| `NUBE_ACME_WEBROOT` | `/var/www/acme` | Webroot del challenge HTTP-01 |
| `NUBE_NGINX_SSL_DIR` | `/etc/nginx/ssl` | Destino de los certificados |
| `NUBE_NGINX_DIR` | `/etc/nginx` | Configuración de nginx que se aplica |
| `NUBE_FAIL2BAN_DIR` | `/etc/fail2ban` | Configuración de fail2ban que se aplica |
| `NUBE_MYSQL_HOST` | `127.0.0.1` | Host de MySQL |
| `NUBE_MYSQL_PORT` | `3306` | Puerto de MySQL |
| `NUBE_SECRETS_FILE` | `$HOME/secrets.gpg` | Credenciales cifradas |
| `NUBE_DEPLOY_LOG` | `$HOME/nube-deploy.log` | Log de deploys |
| `NUBE_SERVER_REPO` | `/home/<usuario>/git/nube.git` | Repositorio del servidor |
| `NUBE_SERVER_SRC` | `/srv/nube` | Copia de trabajo de la configuración |
| `NUBE_SERVER_REF` | `main` | Rama que se aplica en cada push |
| `NUBE_HOOK_BIN` | `/usr/local/bin/nube-hook-post-update` | Hook de las apps |
| `NUBE_APPLY_BIN` | `/usr/local/bin/nube-apply-config` | Aplica la config del servidor |
| `NUBE_NO_INTERACTIVE_LOGIN` | `/usr/local/lib/nube/no-interactive-login.sh` | Mensaje de git-shell |
| `NUBE_GIT_SHELL` | `/usr/bin/git-shell` | Shell del usuario de deploy |

También se pueden pasar por entorno
(`NUBE_BASE_DOMAIN=... nube-add-repository ...`), pero en general conviene el
archivo de configuración.

`NUBE_CONFIG=/ruta/alternativa` permite usar otro archivo.

## Archivos

### Instalación

| Ruta | Contenido |
| --- | --- |
| `/opt/nube/` | Repositorio clonado (tu fork) |
| `/srv/nube/` | Copia de trabajo desde la que se aplica la config |
| `/usr/local/lib/nube/` | Scripts y `lib/nube.sh` |
| `/usr/local/bin/` | Comandos instalados como symlinks a los scripts: `nube-add-repository`, `nube-add-domain`, `nube-add-subdomain` y `nube-*` |
| `/etc/nube/nube.conf` | Configuración |
| `/etc/sudoers.d/nube` | Permisos acotados del usuario de deploy |
| `/var/www/<dominio>` | Symlink al sitio |
| `/var/www/acme` | Challenge HTTP-01 |
| `/etc/nginx/ssl/<dominio>/` y `nube.crt` | Certificados |
| `/etc/nginx/.nube-backup-*` | Backup de la última config de nginx aplicada |

### Del usuario de deploy

| Ruta | Contenido |
| --- | --- |
| `~/git/nube.git` | Repositorio del servidor (aplica la config) |
| `~/git/<app>.git` | Repositorio bare de cada app |
| `~/www/<dominio>/public` | Web root |
| `~/secrets.gpg` | `NUBE_DB_USER`, `NUBE_DB_PASS` |
| `~/nube-deploy.log` | Salida de deploys |
| `~/.ssh/authorized_keys` | Claves de push |
| `~/.ssh/id_ed25519` | Clave para dependencias privadas |
| `~/git-shell-commands/no-interactive-login` | Mensaje al entrar por SSH |

## Base de datos

Nombre de base por dominio:

```text
blog.example.com  ->  blog_example_com
mi-app.site.com   ->  mi_app_site_com
```

Usuario: `<NUBE_USER>_<12 hex>`, creado por `nube-init-user`.

## Git

```bash
# Configuracion del servidor
git remote add server nube@nube.example.com:git/nube
git push server main

# App
git remote add prod nube@nube.example.com:git/blog
git remote add prod ssh://nube@nube.example.com/home/nube/git/blog.git

# Deploy
git push prod main

# Rollback
git push --force prod <sha>:main

# Ver el hook que corre el servidor
ssh nube@nube.example.com   # muestra el mensaje de no-interactive-login
```

## Nginx

| Ruta | Qué |
| --- | --- |
| `/etc/nginx/nginx.conf` | Configuración principal |
| `/etc/nginx/conf.d/nube.conf` | Server blocks |
| `/etc/nginx/snippets/nube-*.conf` | Snippets de Nube |
| `/var/log/nginx/access.log` | Formato `nube` (usado por fail2ban) |

Se editan en [`nginx/`](../../nginx/) del repositorio y se aplican con
`git push server main`.

## fail2ban

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd unbanip <ip>
sudo tail -f /var/log/fail2ban.log
```

## systemd

```bash
sudo systemctl {status,reload,restart} nginx php8.3-fpm mariadb fail2ban
sudo journalctl -u <servicio> -n 100 --no-pager
```
