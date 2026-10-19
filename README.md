# Nube

[![Demo: subir una app hecha en PHP a Nube desde git](docs/img/demo.gif)](https://asciinema.org/a/449183)

▶️ Demo: [subir una app hecha en PHP a Nube desde `git push`](https://asciinema.org/a/449183).
El GIF de arriba es la grabación acelerada; en asciinema podés pausarla,
copiar los comandos y cambiar la velocidad.

**Tu propio mini-PaaS sobre un VPS con Ubuntu.** Hacés `git push` y la app
queda publicada con HTTPS, base de datos y logs, sin depender de un proveedor
de PaaS.

Nube usa **un solo usuario de deploy** y **un dominio base**. El repositorio
que estás leyendo es, además, la configuración del servidor: si hacés push a
tu fork apuntando al VPS, Nube copia `nginx/` y `fail2ban/` a `/etc` y deja el
servidor actualizado.

```bash
# Configuracion del servidor (nginx, fail2ban, scripts)
git push server main

# Una app
git remote add prod nube@nube.example.com:git/mi-app
git push prod main
# ...
# Listo → https://mi-app.nube.example.com
```

> Si recién empezás con servidores, dominios y DNS, la guía
> [Introducción: servidor, VPS, dominio y DNS](docs/00-introduccion.md) explica
> los conceptos antes de tocar una terminal. Está inspirada en la
> [guía para subir webs a hosting o VPS](https://blog.albo.ar/guia-para-subir-webs-a-hosting-o-vps.html).

## Cómo funciona

Hay dos flujos de `git push`: uno para la configuración del servidor y otro
para cada app.

```text
  Tu máquina                          VPS Ubuntu
  ──────────                          ─────────────────────────────────────────
  git push server main
        │                             ~/git/nube.git   (repositorio del servidor)
        ▼                                   │
  SSH (git-shell) ──────────────────▶  hooks/post-receive
                                            │
                                            ▼
                                     nube-apply-config
                                            │
                      ┌─────────────────────┼─────────────────────┐
                      ▼                     ▼                     ▼
                 /usr/local            /etc/nginx            /etc/fail2ban
                 (comandos)     (nginx.conf, conf.d,       (filters, jail)
                                 snippets)
                                            │
                                            ▼
                                    nginx -t + reload

  git push prod main
        │                             ~/git/<app>.git  (repositorio de la app)
        ▼                                   │
  SSH (git-shell) ──────────────────▶  hooks/post-update
                                            │
                                            ▼
                                     nube-hook-post-update
                                            │
                      ┌─────────────────────┼─────────────────────┐
                      ▼                     ▼                     ▼
               checkout en             .env + composer      migraciones /
               /var/www/<dominio>      + caches             hooks propios
                      │
                      ▼
  HTTPS  ──────▶  nginx  ──────▶  PHP-FPM (www-data)  ──────▶  MySQL/MariaDB
                   │
                   └── /var/www/<dominio>/public
```

El servidor tiene:

- **un usuario de deploy** (`nube`) con `git-shell` (sin shell interactivo);
- **un repositorio del servidor** (`~/git/nube.git`) que aplica la
  configuración al recibir un push;
- **un repositorio bare por app** en `~/git/<app>.git`;
- una carpeta web por dominio en `~/www/<dominio>/public`, expuesta por un
  symlink en `/var/www/<dominio>`;
- **un usuario y una base de MySQL por app**;
- credenciales cifradas con GPG en `~/secrets.gpg`;
- un hook que hace el deploy en cada push.

## Qué incluye

| Pieza | Detalle |
| --- | --- |
| Config del servidor por `git push` | `bootstrap.sh` + `nube-apply-config` + `nginx/`, `fail2ban/` |
| Deploy por `git push` | Hook `post-update` + `nube-hook-post-update` |
| Usuario aislado | `git-shell`, home restringido, claves SSH |
| Dominios y subdominios | `nube-add-domain`, `nube-add-subdomain` y `nube-add-repository` |
| HTTPS | `acme.sh` (HTTP-01 o DNS-01 para wildcard) |
| PHP / Laravel | `composer install`, `.env`, caches, migraciones |
| Node.js | `npm ci`, `npm run build` y recarga de PM2 si hay `ecosystem.config.js` |
| Python | `.venv` + `pip install` desde `requirements.txt` o `pyproject.toml` |
| Sitios estáticos | Cualquier `index.html` dentro de `public/` |
| Base de datos | Un usuario y una base por app (MySQL/MariaDB) |
| Seguridad | fail2ban, UFW, hardening de SSH/nginx, guía de buenas prácticas |
| Operación | Backups, logs, actualizaciones y troubleshooting documentados |

## Inicio rápido

Requisitos: un VPS con Ubuntu 24.04 LTS, un dominio y acceso root por SSH. El
detalle está en [Preparar el servidor](docs/01-preparar-ubuntu.md) y
[Dominio y DNS](docs/02-dominio-y-dns.md).

```bash
# 1. En el servidor: clonar TU fork y preparar Nube
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/TU-USUARIO/vps.git /opt/nube
cd /opt/nube
sudo ./bootstrap.sh --base-domain nube.example.com \
    --email yo@example.com --ssh-key-file ~/.ssh/id_ed25519.pub

# 2. En tu máquina: apuntar tu fork al servidor
git remote add server nube@nube.example.com:git/nube
git push server main          # aplica nginx, fail2ban y los comandos

# 3. Crear una app y su base de datos
sudo runuser -u nube -- nube-add-subdomain app
sudo runuser -u nube -- nube-add-repository app app.nube.example.com | sudo mysql

# 4. Publicarla
git remote add prod nube@nube.example.com:git/app
git push prod main
```

Al terminar el push de una app vas a ver el detalle del deploy y la URL. Si
algo falla, el hook devuelve error y deja el detalle en `~/nube-deploy.log`.
Si falla la configuración de nginx, el push del servidor la revierte y muestra
el error de `nginx -t`.

Para un **dominio propio** en lugar de un subdominio, usá
`nube-add-domain app.example.com` en el paso 3 (requiere acme.sh instalado
para el usuario; ver [02 · Dominio y DNS](docs/02-dominio-y-dns.md)).

## Cómo usar tu fork

Nube está pensado para que cada servidor tenga su propio fork del repositorio:

1. Hacé **fork** de `github.com/4lb0/vps` en tu cuenta.
2. Cloná **tu fork** en el VPS (paso 1 del inicio rápido).
3. Trabajá en local sobre tu fork y publicá los cambios en el servidor con
   `git push server main`.

Así podés adaptar nginx, fail2ban y los scripts sin afectar a nadie más, y
cada push deja el servidor con exactamente lo que está en tu repositorio. Si
más adelante querés incorporar mejoras del repositorio original, agregalo como
remoto `upstream` y hacé `git merge upstream/main`.

## Comandos

| Comando | Quién lo ejecuta | Qué hace |
| --- | --- | --- |
| `sudo ./bootstrap.sh ...` | root (una vez) | Configuración, usuario, repositorio del servidor y sudoers |
| `sudo ./install.sh [origen]` | root | Aplica scripts + `nginx/` + `fail2ban/` |
| `sudo nube-apply-config` | root | Vuelve a aplicar la config del repositorio del servidor |
| `sudo nube-init-user [clave]` | root | Crea el usuario de deploy, su MySQL y `secrets.gpg` |
| `sudo runuser -u nube -- nube-add-domain <dominio>` | root | Prepara un dominio propio y emite TLS |
| `sudo runuser -u nube -- nube-add-subdomain <subdominio>` | root | Prepara `<subdominio>.<base>` |
| `sudo runuser -u nube -- nube-add-repository <app> [dominio]` | root | Crea el repo bare y el hook; imprime SQL |
| `nube-add-repository`, `nube-add-domain`, `nube-add-subdomain` | usuario de deploy | Igual que arriba, si ya estás como ese usuario |
| `nube-hook-post-update` | git | Hook interno de deploy de una app |
| `nube-motd` | login | Banner del servidor |
| `create-project.sh <app> <template> <origen> [prod]` | tu máquina | Crea un proyecto y configura `origin` y `prod` |
| `make lint` | tu máquina | Valida la sintaxis de todos los scripts |

Referencia completa: [Comandos y variables](docs/referencia/comandos.md).

## Documentación

| Guía | Para qué |
| --- | --- |
| [00 · Introducción](docs/00-introduccion.md) | Servidor, VPS, hosting, dominio y DNS desde cero |
| [01 · Preparar Ubuntu](docs/01-preparar-ubuntu.md) | Crear el VPS e instalar nginx, PHP, MySQL, Node, Python y acme.sh |
| [02 · Dominio y DNS](docs/02-dominio-y-dns.md) | Registrar el dominio, apuntarlo y configurar wildcard |
| [03 · Instalar Nube](docs/03-instalar-nube.md) | `bootstrap.sh`, `install.sh`, `/etc/nube/nube.conf` y nginx |
| [04 · El usuario y las apps](docs/04-usuario-y-apps.md) | El usuario de deploy, dominios, repositorios y bases |
| [05 · Deploy con git](docs/05-deploy-con-git.md) | Cómo funciona el push, `.env`, Laravel, Node, Python y rollback |
| [06 · Seguridad](docs/06-seguridad.md) | SSH, fail2ban, UFW, nginx, PHP-FPM, MySQL y secretos |
| [07 · Operación y backups](docs/07-operacion-y-backups.md) | Logs, actualizaciones, backups y restauración |
| [08 · Solución de problemas](docs/08-solucion-de-problemas.md) | Errores comunes y cómo diagnosticarlos |
| [Referencia · Arquitectura](docs/referencia/arquitectura.md) | Flujo de un request y de un deploy |
| [Referencia · Comandos](docs/referencia/comandos.md) | Scripts, variables y archivos |
| [Referencia · Plantillas](docs/referencia/plantillas.md) | `.env`, hooks propios y ejemplos |

También hay ejemplos listos para copiar en [`docs/ejemplos/`](docs/ejemplos/):
systemd para Node y un script de backup. La configuración de nginx que Nube
instala está en [`nginx/`](nginx/).

## Seguridad

Nube está pensado para un VPS propio. Antes de publicar algo real:

1. Seguí la [guía de seguridad](docs/06-seguridad.md).
2. Instalá el [jail de fail2ban](fail2ban/README.md).
3. Tené en cuenta que quien puede hacer push al repositorio del servidor puede
   instalar configuración como root (es el objetivo del proyecto). Protegé esa
   clave y no la compartas.
4. Configurá backups y probá una restauración.

Para reportar una vulnerabilidad, leé [`SECURITY.md`](SECURITY.md).

## Alcance

Nube es deliberadamente chico y transparente:

- **PHP y Laravel** funcionan out of the box.
- **Node y Python** instalan sus dependencias en el deploy (`npm`/`pip`);
  el proceso vivo y el proxy en nginx se configuran una vez con las recetas.
- **Sitios estáticos** funcionan poniendo los archivos en `public/`.
- **Go o Docker** se pueden correr con systemd o Docker;
  hay recetas en [Deploy con git](docs/05-deploy-con-git.md).
- Es **un VPS, un usuario de deploy y un dominio base**. No es un hosting
  multi-tenant: si necesitás alojar clientes que no confían entre sí, usá un
  VPS por cliente.
- No hay panel web, ni autoescalado, ni deploy blue/green.

## Licencia

[MIT](LICENSE) © 2026 Rodrigo Arce.

## Créditos

Inspirado en la guía [“Guía para subir webs a Hosting o VPS”](https://blog.albo.ar/guia-para-subir-webs-a-hosting-o-vps.html)
de [albo.ar](https://albo.ar).
