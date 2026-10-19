# 03 · Instalar Nube

Esta guía asume que ya tenés el servidor listo
([01](01-preparar-ubuntu.md)) y el dominio con wildcard apuntando al VPS
([02](02-dominio-y-dns.md)).

La idea central: **el repositorio es la configuración del servidor**. Lo clonás
(idealmente un fork tuyo), corrés `bootstrap.sh` una vez y después aplicás
cambios con `git push server main`.

## 1. Forkear y clonar el repositorio

Hacé un fork de `github.com/4lb0/vps` en tu cuenta de GitHub y cloná **tu
fork** en el servidor:

```bash
sudo apt install -y git
sudo git clone https://github.com/TU-USUARIO/vps.git /opt/nube
cd /opt/nube
ls
```

Queda en `/opt/nube`. Si preferís `/srv`, `/root` o tu home, cambialo; los
scripts no dependen de la ruta.

> Con el fork podés adaptar `nginx/`, `fail2ban/` y los scripts a tu gusto. Si
> querés recibir mejoras del original, agregalo como remoto:
> `git remote add upstream https://github.com/4lb0/vps.git`.

## 2. Preparar el servidor con bootstrap.sh

```bash
sudo ./bootstrap.sh \
    --base-domain nube.example.com \
    --email yo@example.com \
    --ssh-key-file ~/.ssh/id_ed25519.pub
```

| Opción | Para qué |
| --- | --- |
| `--base-domain` | Dominio base de los subdominios (`NUBE_BASE_DOMAIN`) |
| `--email` | Email del usuario de deploy (identidad de la clave GPG) |
| `--ssh-key-file` / `--ssh-key` | Clave pública que puede hacer `git push` |
| `--user` | Usuario de deploy (por defecto `nube`) |
| `--php` | Versión de PHP, para el `fastcgi_pass` de nginx (por defecto `8.3`) |

`bootstrap.sh` es idempotente y hace todo esto:

| Acción | Destino |
| --- | --- |
| Crea/ajusta la configuración | `/etc/nube/nube.conf` |
| Copia los scripts | `/usr/local/lib/nube/` |
| Crea los comandos en `/usr/local/bin` | `nube-init-user`, `nube-add-repository`, `nube-add-domain`, `nube-add-subdomain`, `nube-apply-config`, `nube-hook-post-update`, `nube-motd` |
| Aplica la configuración de nginx | `/etc/nginx/{nginx.conf,conf.d/nube.conf,snippets/nube-*.conf}` |
| Aplica la configuración de fail2ban | `/etc/fail2ban/` |
| Crea el usuario de deploy | `/home/<usuario>` con `git-shell`, MySQL y `secrets.gpg` |
| Crea el repositorio del servidor | `~/git/nube.git` + hook `post-receive` |
| Habilita el sudoers acotado | `/etc/sudoers.d/nube` |

El sudoers permite al usuario de deploy ejecutar, **sin contraseña**:

```sudoers
nube ALL=(root) NOPASSWD: /usr/local/bin/nube-apply-config, /usr/bin/systemctl reload nginx, /usr/sbin/nginx -t
```

Son justo los comandos que necesitan el hook del repositorio del servidor y
`nube-add-domain` para recargar nginx al emitir certificados. No da shell ni
sudo general: el usuario sigue con `git-shell`.

Comprobá:

```bash
command -v nube-add-repository nube-add-domain nube-add-subdomain nube-init-user nube-apply-config
sudo -l -U nube
```

## 3. Configurar `/etc/nube/nube.conf`

Si ya pasaste `--base-domain`, `--user`, `--email` y `--php`, no hace falta
tocar nada. Igual conviene revisarlo:

```bash
sudo nano /etc/nube/nube.conf
```

| Variable | Default | Qué es |
| --- | --- | --- |
| `NUBE_USER` | `nube` | El único usuario de deploy |
| `NUBE_USER_MAIL` | vacío | Email de la clave GPG (`<usuario>@<host>` si está vacío) |
| `NUBE_BASE_DOMAIN` | `nube.example.com` | Dominio base de los subdominios automáticos |
| `NUBE_WEB_ROOT` | `/var/www` | Directorio de los symlinks públicos |
| `NUBE_WEB_GROUP` | `www-data` | Grupo con acceso a los sitios y a `storage/` |
| `NUBE_SSH_GROUP` | `nube` | Grupo con acceso SSH (para `AllowGroups`) |
| `NUBE_PHP_VERSION` | `8.3` | Versión de PHP (socket de nginx) |
| `NUBE_ACME_HOME` | `$HOME/.acme.sh` | acme.sh del usuario que ejecuta `nube-add-domain` |
| `NUBE_ACME_MODE` | `webroot` | `webroot`, `stateless` o `none` |
| `NUBE_ACME_WEBROOT` | `/var/www/acme` | Webroot del challenge HTTP-01 |
| `NUBE_NGINX_SSL_DIR` | `/etc/nginx/ssl` | Dónde van los certificados |
| `NUBE_MYSQL_HOST` | `127.0.0.1` | Host de MySQL |
| `NUBE_MYSQL_PORT` | `3306` | Puerto de MySQL |
| `NUBE_SECRETS_FILE` | `$HOME/secrets.gpg` | Credenciales cifradas |
| `NUBE_DEPLOY_LOG` | `$HOME/nube-deploy.log` | Log de deploys |
| `NUBE_SERVER_REPO` | `/home/<usuario>/git/nube.git` | Repositorio del servidor |
| `NUBE_SERVER_SRC` | `/srv/nube` | Copia de trabajo de la config |
| `NUBE_SERVER_REF` | `main` | Rama que se aplica en cada push |
| `NUBE_HOOK_BIN` | `/usr/local/bin/nube-hook-post-update` | Binario que ejecuta el hook de las apps |
| `NUBE_APPLY_BIN` | `/usr/local/bin/nube-apply-config` | Aplica la config del servidor |
| `NUBE_NO_INTERACTIVE_LOGIN` | `/usr/local/lib/nube/no-interactive-login.sh` | Mensaje de git-shell |
| `NUBE_GIT_SHELL` | `/usr/bin/git-shell` | Shell del usuario de deploy |

`/etc/nube/nube.conf` **no debe contener secretos**: lo lee el usuario de
deploy. Si cambiás cualquier valor, volvé a aplicar la configuración:

```bash
sudo ./install.sh /opt/nube     # desde el clon (si todavia no hay push)
sudo nube-apply-config          # desde el repositorio del servidor (tras un push)
```

### Verificación rápida

```bash
sudo runuser -u nobody -- bash -c '. /usr/local/lib/nube/lib.sh; echo "$NUBE_USER $NUBE_BASE_DOMAIN $NUBE_WEB_ROOT"'
```

## 4. nginx

La configuración de nginx vive en [`nginx/`](../nginx/) y `install.sh` la
copia a `/etc/nginx/` reemplazando los placeholders `#NUBE_*#` por los valores
de `/etc/nube/nube.conf`:

| Archivo | Destino |
| --- | --- |
| `nginx/nginx.conf` | `/etc/nginx/nginx.conf` |
| `nginx/conf.d/nube.conf` | `/etc/nginx/conf.d/nube.conf` |
| `nginx/snippets/*.conf` | `/etc/nginx/snippets/` |

Antes de recargar, Nube corre `nginx -t`. Si falla, **restaura la configuración
anterior** y avisa con el error. Detalle en [`nginx/README.md`](../nginx/README.md).

Puntos a revisar:

1. `fastcgi_pass unix:/run/php/php8.3-fpm.sock` coincide con tu versión de PHP
   (`NUBE_PHP_VERSION`).
2. Esta configuración **no** incluye `/etc/nginx/sites-enabled`: el sitio
   `default` de Ubuntu queda fuera. Si tenías sitios ahí, migralos a
   `conf.d/`.
3. Mientras no emitas el certificado wildcard, nginx usa un certificado
   autofirmado que deja `install.sh`. El navegador va a protestar hasta que lo
   reemplaces (paso 5).

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

## 6. Aplicar cambios con `git push`

Desde tu máquina, apuntá tu fork al servidor:

```bash
git remote add server nube@TU-DOMINIO-BASE:git/nube
git push server main
```

Qué pasa en el servidor:

1. `git-receive-pack` actualiza `~/git/nube.git`;
2. `hooks/post-receive` llama a `nube-apply-config` (con el sudoers acotado);
3. `nube-apply-config` hace checkout de `main` en `/srv/nube`;
4. se ejecuta el `install.sh` de esa copia: scripts, nginx y fail2ban;
5. si `nginx -t` pasa, nginx se recarga; si no, se revierte y el push falla.

Así, cualquier cambio en `nginx/`, `fail2ban/` o en los scripts se publica con
un push. Para ver el detalle:

```bash
git push server main       # muestra la salida de install.sh
ssh nube@TU-DOMINIO-BASE   # mensaje de git-shell
sudo nube-apply-config     # aplicar a mano (por ejemplo, tras editar nube.conf)
```

## 7. Permisos (repaso)

| Ruta | Dueño | Modo | Por qué |
| --- | --- | --- | --- |
| `/var/www` | `root:www-data` | `2775` | El usuario crea sus symlinks |
| `/var/www/acme` | `www-data:www-data` | `2775` | Challenge HTTP-01 |
| `/etc/nginx/ssl` | `root:www-data` | `2770` | Certificados |
| `/home/<usuario>` | `<usuario>:www-data` | `0750` | nginx atraviesa, otros no |
| `/home/<usuario>/.ssh` | `<usuario>:<usuario>` | `0700` | Claves SSH |
| `/home/<usuario>/secrets.gpg` | `<usuario>:<usuario>` | `0600` | Credenciales cifradas |
| `/srv/nube` | `root:root` | `0755` | Copia de trabajo de la config |

`install.sh` ajusta las tres primeras. `nube-init-user` ajusta las del home.

## 8. Actualizar Nube

```bash
cd /opt/nube
sudo git pull                       # si actualizás el clon del servidor
sudo ./bootstrap.sh                 # vuelve a aplicar todo (idempotente)
```

O, más simple, desde tu máquina:

```bash
git push server main
```

`install.sh` no sobreescribe `/etc/nube/nube.conf` ni
`/etc/fail2ban/jail.local` si ya existen. Si agregamos una variable nueva,
comparala con `nube.conf.example`.

## Checklist

- [ ] Fork hecho y clonado en `/opt/nube`.
- [ ] `sudo ./bootstrap.sh` sin errores.
- [ ] `nube-add-repository`, `nube-add-domain`, `nube-add-subdomain` disponibles en el PATH.
- [ ] `/etc/nube/nube.conf` con tu dominio base, usuario y PHP.
- [ ] nginx aplicado y `nginx -t` en verde.
- [ ] `git remote add server ...` configurado y `git push server main` probado.
- [ ] Wildcard certificado emitido e instalado.
- [ ] `openssl s_client` devuelve un certificado válido para el dominio base.

Siguiente: [04 · El usuario y las apps](04-usuario-y-apps.md).
