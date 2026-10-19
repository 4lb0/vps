# 03 · Instalar Nube

Esta guía asume que ya tenés el servidor listo
([01](01-preparar-ubuntu.md)) y el dominio con wildcard apuntando al VPS
([02](02-dominio-y-dns.md)).

## 1. Clonar el repositorio

```bash
sudo apt install -y git
sudo git clone https://github.com/4lb0/vps.git /opt/nube
cd /opt/nube
ls
```

Queda en `/opt/nube`. Si preferís `/srv`, `/root` o tu home, cambialo; los
scripts no dependen de la ruta.

## 2. Ejecutar install.sh

```bash
sudo ./install.sh
```

`install.sh` es idempotente (se puede correr de nuevo después de un
`git pull`) y hace lo siguiente:

| Acción | Destino |
| --- | --- |
| Copia los scripts | `/usr/local/lib/nube/` |
| Crea los comandos | `/usr/local/bin/{nr,nd,ns,nube-add-user,nube-hook-post-update,nube-motd}` |
| Crea la configuración | `/etc/nube/nube.conf` (solo si no existe) |
| Ajusta permisos | `/var/www` (2775, grupo `www-data`), `/var/www/acme`, `/etc/nginx/ssl` (2770) |

No toca nginx, MySQL ni usuarios existentes.

Comprobá:

```bash
nr --help 2>/dev/null || nr
command -v nr nd ns nube-add-user nube-hook-post-update
```

## 3. Configurar `/etc/nube/nube.conf`

Editá el archivo:

```bash
sudo nano /etc/nube/nube.conf
```

| Variable | Default | Qué es |
| --- | --- | --- |
| `NUBE_BASE_DOMAIN` | `nube.pragmore.com` | Dominio base de los subdominios automáticos |
| `NUBE_WEB_ROOT` | `/var/www` | Directorio de los symlinks públicos |
| `NUBE_WEB_GROUP` | `www-data` | Grupo con acceso a los sitios y a `storage/` |
| `NUBE_SSH_GROUP` | `nube` | Grupo de usuarios de deploy (para `AllowGroups`) |
| `NUBE_PHP_VERSION` | `8.3` | Versión de PHP instalada (informativa) |
| `NUBE_ACME_HOME` | `$HOME/.acme.sh` | acme.sh del usuario que ejecuta `nd` |
| `NUBE_ACME_MODE` | `webroot` | `webroot`, `stateless` o `none` |
| `NUBE_ACME_WEBROOT` | `/var/www/acme` | Webroot del challenge HTTP-01 |
| `NUBE_NGINX_SSL_DIR` | `/etc/nginx/ssl` | Dónde instala `nd` los certificados |
| `NUBE_MYSQL_HOST` | `127.0.0.1` | Host de MySQL |
| `NUBE_MYSQL_PORT` | `3306` | Puerto de MySQL |
| `NUBE_SECRETS_FILE` | `$HOME/secrets.gpg` | Credenciales cifradas de cada usuario |
| `NUBE_DEPLOY_LOG` | `$HOME/nube-deploy.log` | Log de deploys |
| `NUBE_HOOK_BIN` | `/usr/local/bin/nube-hook-post-update` | Binario que ejecuta el hook |
| `NUBE_NO_INTERACTIVE_LOGIN` | `/usr/local/lib/nube/no-interactive-login.sh` | Mensaje de git-shell |
| `NUBE_GIT_SHELL` | `/usr/bin/git-shell` | Shell restringido de los usuarios |

Los valores por defecto conservan el comportamiento del servidor original
(`nube.pragmore.com`). En una instalación nueva cambiá al menos
`NUBE_BASE_DOMAIN` y verificá `NUBE_ACME_HOME`.

`/etc/nube/nube.conf` **no debe contener secretos**: lo leen todos los
usuarios de deploy.

### Verificación rápida

```bash
sudo runuser -u nobody -- bash -c '. /usr/local/lib/nube/lib.sh; echo "$NUBE_BASE_DOMAIN $NUBE_WEB_ROOT"'
```

## 4. Configurar nginx

Podés partir de la configuración de ejemplo incluida:

```bash
cd /opt/nube

sudo cp docs/ejemplos/nginx/nginx.conf /etc/nginx/nginx.conf
sudo cp docs/ejemplos/nginx/nube.conf  /etc/nginx/conf.d/nube.conf
sudo install -d /etc/nginx/snippets
sudo cp docs/ejemplos/nginx/snippets/*.conf /etc/nginx/snippets/

# Reemplazar por tu dominio base
sudo sed -i 's/nube\.example\.com/TU-DOMINIO-BASE/g' \
  /etc/nginx/nginx.conf /etc/nginx/conf.d/nube.conf

sudo nginx -t
sudo systemctl reload nginx
```

Detalle de cada archivo en
[`docs/ejemplos/nginx/README.md`](ejemplos/nginx/README.md).

Puntos a revisar antes de recargar:

1. `fastcgi_pass unix:/run/php/php8.3-fpm.sock` coincide con tu versión de PHP.
2. El `root /var/www/$app.<base>/public` usa tu dominio base.
3. `ssl_certificate /etc/nginx/ssl/nube.crt|key` apunta al wildcard emitido en
   el paso siguiente.
4. Si Ubuntu te dejó `/etc/nginx/sites-enabled/default`, borralo o quitá su
   `default_server` para que no compita con `nube.conf`.

> Si todavía no emitiste el wildcard, `nginx -t` va a fallar con
> "cannot load certificate". Emitilo primero (paso 5) o comentá los bloques
> HTTPS hasta tenerlo.

## 5. Certificado wildcard

Si no lo hiciste en [02](02-dominio-y-dns.md#5-certificado-wildcard-para-nubeexamplecom):

```bash
export CF_Token="tu-token"   # u otro proveedor DNS
sudo mkdir -p /etc/nginx/ssl

sudo -E /root/.acme.sh/acme.sh --issue --dns dns_cf \
  -d '*.TU-DOMINIO-BASE' -d TU-DOMINIO-BASE \
  --keylength ec-256

sudo /root/.acme.sh/acme.sh --install-cert \
  -d '*.TU-DOMINIO-BASE' --ecc \
  --key-file       /etc/nginx/ssl/nube.key \
  --fullchain-file /etc/nginx/ssl/nube.crt \
  --reloadcmd      "systemctl reload nginx"
```

Comprobá:

```bash
sudo nginx -t && sudo systemctl reload nginx
openssl s_client -connect TU-DOMINIO-BASE:443 -servername test.TU-DOMINIO-BASE </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
```

## 6. Permisos (repaso)

| Ruta | Dueño | Modo | Por qué |
| --- | --- | --- | --- |
| `/var/www` | `root:www-data` | `2775` | Los usuarios crean sus symlinks |
| `/var/www/acme` | `www-data:www-data` | `2775` | Challenge HTTP-01 |
| `/etc/nginx/ssl` | `root:www-data` | `2770` | Cada usuario instala su certificado |
| `/home/<user>` | `<user>:www-data` | `0750` | nginx atraviesa, otros no |
| `/home/<user>/.ssh` | `<user>:<user>` | `0700` | Claves SSH |
| `/home/<user>/secrets.gpg` | `<user>:<user>` | `0600` | Credenciales cifradas |

`install.sh` ajusta las tres primeras. `add-user.sh` ajusta las del home.

## 7. Actualizar Nube

```bash
cd /opt/nube
sudo git pull
sudo ./install.sh
sudo systemctl reload nginx   # solo si cambiaron archivos de nginx
```

`install.sh` no sobreescribe `/etc/nube/nube.conf`. Si agregamos una variable
nueva, comparala con `nube.conf.example`.

## Checklist

- [ ] Repo clonado en `/opt/nube`.
- [ ] `sudo ./install.sh` sin errores.
- [ ] `nr`, `nd`, `ns` disponibles en el PATH.
- [ ] `/etc/nube/nube.conf` con tu dominio base y PHP.
- [ ] nginx configurado y `nginx -t` en verde.
- [ ] Wildcard certificado emitido e instalado.
- [ ] `openssl s_client` devuelve un certificado válido para el dominio base.

Siguiente: [04 · Usuarios y apps](04-usuarios-y-aplicaciones.md).
