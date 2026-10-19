# Comandos y variables

Referencia de la interfaz de Nube.

## Comandos

### `nube-add-user <usuario> <email> [<clave-publica>]`

Alias: `add-user.sh`. Requiere **root**.

Crea el usuario de deploy con `git-shell`, su usuario de MySQL, `secrets.gpg`
y la clave SSH. Detalle en
[04 · Usuarios y apps](../04-usuarios-y-aplicaciones.md#2-crear-un-usuario).

### `nr <app> [<dominio>]`

Alias interno: `add-repository.sh`. Se ejecuta **como el usuario de deploy**.

Crea/actualiza `~/git/<app>.git` y su hook, asegura el directorio web e
imprime el SQL de MySQL por stdout.

```bash
sudo runuser -u juan -- nr blog blog.example.com | sudo mysql
```

Errores posibles: nombre o dominio inválido, permisos en `/var/www`, falta de
`secrets.gpg`.

### `nd <dominio>`

Alias interno: `add-domain.sh`. Como el usuario de deploy.

Crea el sitio, la página inicial y emite/instala el certificado según
`NUBE_ACME_MODE`. Ver
[04](../04-usuarios-y-aplicaciones.md#4-crear-una-app-en-un-dominio-propio).

### `ns <subdominio>`

Alias interno: `add-subdomain.sh`. Como el usuario de deploy.

Crea `<subdominio>.<NUBE_BASE_DOMAIN>`. No emite certificado (lo cubre el
wildcard).

### `nube-hook-post-update <ref> <dominio> <git-dir>`

Hook interno. Lo invoca `hooks/post-update`. No se ejecuta a mano.

Variables que acepta del entorno del servidor:

| Variable | Efecto |
| --- | --- |
| `NUBE_SKIP_COMPOSER=1` | No corre `composer install` |
| `NUBE_SKIP_MIGRATIONS=1` | No corre `php artisan migrate` |
| `NUBE_SKIP_ARTISAN_CACHE=1` | No corre `config:cache`, `route:cache`, `view:cache` |

### `nube-motd`

Banner de login. Se puede instalar en `/etc/profile.d/` o `/etc/motd`.

### `test-hook.sh [ruta] [remoto] [url]`

Prueba de humo del deploy desde tu máquina.

## Variables de `/etc/nube/nube.conf`

| Variable | Default | Descripción |
| --- | --- | --- |
| `NUBE_BASE_DOMAIN` | `nube.pragmore.com` | Dominio base de los subdominios |
| `NUBE_WEB_ROOT` | `/var/www` | Directorio de symlinks |
| `NUBE_WEB_GROUP` | `www-data` | Grupo con acceso a los sitios |
| `NUBE_SSH_GROUP` | `nube` | Grupo de usuarios de deploy |
| `NUBE_PHP_VERSION` | `8.3` | Versión de PHP (informativa) |
| `NUBE_ACME_HOME` | `$HOME/.acme.sh` | acme.sh del usuario que corre `nd` |
| `NUBE_ACME_MODE` | `webroot` | `webroot`, `stateless` o `none` |
| `NUBE_ACME_WEBROOT` | `/var/www/acme` | Webroot del challenge HTTP-01 |
| `NUBE_NGINX_SSL_DIR` | `/etc/nginx/ssl` | Destino de los certificados |
| `NUBE_MYSQL_HOST` | `127.0.0.1` | Host de MySQL |
| `NUBE_MYSQL_PORT` | `3306` | Puerto de MySQL |
| `NUBE_SECRETS_FILE` | `$HOME/secrets.gpg` | Credenciales cifradas |
| `NUBE_DEPLOY_LOG` | `$HOME/nube-deploy.log` | Log de deploys |
| `NUBE_HOOK_BIN` | `/usr/local/bin/nube-hook-post-update` | Hook |
| `NUBE_NO_INTERACTIVE_LOGIN` | `/usr/local/lib/nube/no-interactive-login.sh` | Mensaje de git-shell |
| `NUBE_GIT_SHELL` | `/usr/bin/git-shell` | Shell de los usuarios |

También se pueden pasar por entorno (`NUBE_BASE_DOMAIN=... nr ...`), pero en
general conviene el archivo de configuración.

`NUBE_CONFIG=/ruta/alternativa` permite usar otro archivo.

## Archivos

### Instalación

| Ruta | Contenido |
| --- | --- |
| `/opt/nube/` | Repositorio clonado |
| `/usr/local/lib/nube/` | Scripts y `lib/nube.sh` |
| `/usr/local/bin/nr`, `nd`, `ns`, `nube-*` | Symlinks a los scripts |
| `/etc/nube/nube.conf` | Configuración |
| `/var/www/<dominio>` | Symlink al sitio |
| `/var/www/acme` | Challenge HTTP-01 |
| `/etc/nginx/ssl/<dominio>/` | Certificados por dominio |

### Por usuario

| Ruta | Contenido |
| --- | --- |
| `~/git/<app>.git` | Repositorio bare |
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

Usuario: `<usuario>_<12 hex>`, creado por `add-user.sh`.

## Git

```bash
# Remoto
git remote add prod juan@nube.example.com:git/blog
git remote add prod ssh://juan@nube.example.com/home/juan/git/blog.git

# Deploy
git push prod main

# Rollback
git push --force prod <sha>:main

# Ver el hook que corre el servidor
ssh juan@nube.example.com   # muestra el mensaje de no-interactive-login
```

## Nginx

| Ruta | Qué |
| --- | --- |
| `/etc/nginx/nginx.conf` | Configuración principal |
| `/etc/nginx/conf.d/nube.conf` | Server blocks |
| `/etc/nginx/snippets/nube-*.conf` | Snippets de Nube |
| `/var/log/nginx/access.log` | Formato `nube` (usado por fail2ban) |

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
