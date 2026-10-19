# Nube

**Tu propio mini-Heroku sobre un VPS con Ubuntu.** Hacés `git push` y la app
queda publicada con HTTPS, base de datos y logs, sin depender de un proveedor
de PaaS.

Nube nació como los scripts del servidor `nube.pragmore.com` y hoy está
pensado para que cualquiera pueda contratar un VPS, apuntar un dominio y
publicar sus proyectos con el mismo flujo:

```bash
git remote add prod juan@nube.example.com:git/mi-app
git push prod main
# ...
# Listo → https://mi-app.nube.example.com
```

> Si recién empezás con servidores, dominios y DNS, la guía
> [Introducción: servidor, VPS, dominio y DNS](docs/00-introduccion.md) explica
> los conceptos antes de tocar una terminal. Está inspirada en la
> [guía para subir webs a hosting o VPS](https://blog.albo.ar/guia-para-subir-webs-a-hosting-o-vps.html).

## Cómo funciona

```text
  Tu máquina                          VPS Ubuntu
  ──────────                          ──────────────────────────────────────────
  git push prod main
        │
        ▼
  SSH (git-shell)  ──────────────▶  ~/git/<app>.git  (repositorio bare)
                                          │
                                          │ hooks/post-update
                                          ▼
                                    nube-hook-post-update
                                          │
                     ┌────────────────────┼────────────────────┐
                     ▼                    ▼                    ▼
              checkout en           .env + composer       migraciones /
              /var/www/<dominio>    + caches              hooks propios
                     │
                     ▼
  HTTPS  ──────▶  nginx  ──────▶  PHP-FPM (www-data)  ──────▶  MySQL/MariaDB
                  │
                  └── /var/www/<dominio>/public
```

Cada app tiene:

- un usuario Linux con `git-shell` (sin shell interactivo);
- un repositorio bare en `~/git/<app>.git`;
- una carpeta web en `~/www/<dominio>/public`, expuesta por un symlink en
  `/var/www/<dominio>`;
- un usuario y una base de datos MySQL propios;
- credenciales cifradas con GPG en `~/secrets.gpg`;
- un hook que hace el deploy en cada push.

## Qué incluye

| Pieza | Detalle |
| --- | --- |
| Deploy por `git push` | Hook `post-update` + `nube-hook-post-update` |
| Aislamiento de usuarios | `git-shell`, home restringido, claves SSH |
| Dominios y subdominios | `nd`, `ns` y `nr` |
| HTTPS | `acme.sh` (HTTP-01 o DNS-01 para wildcard) |
| PHP / Laravel | `composer install`, `.env`, caches, migraciones |
| Sitios estáticos | Cualquier `index.html` dentro de `public/` |
| Base de datos | Un usuario y una base por app (MySQL/MariaDB) |
| Seguridad | fail2ban, UFW, hardening de SSH/nginx, guía de buenas prácticas |
| Operación | Backups, logs, actualizaciones y troubleshooting documentados |

## Inicio rápido

Requisitos: un VPS con Ubuntu 24.04 LTS, un dominio y acceso root por SSH.
El detalle está en [Preparar el servidor](docs/01-preparar-ubuntu.md) y
[Dominio y DNS](docs/02-dominio-y-dns.md).

```bash
# 1. Instalar Nube en el servidor
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/4lb0/vps.git /opt/nube
cd /opt/nube
sudo ./install.sh
sudo nano /etc/nube/nube.conf     # dominio base, PHP, acme.sh

# 2. Crear un usuario de deploy
sudo nube-add-user juan juan@example.com "ssh-ed25519 AAAA... juan@laptop"

# 3. Crear la app y su base de datos
sudo runuser -u juan -- ns app
sudo runuser -u juan -- nr app app.nube.example.com | sudo mysql

# 4. Desde tu máquina
git remote add prod juan@nube.example.com:git/app
git push prod main
```

Al terminar el push vas a ver el detalle del deploy y la URL. Si algo falla,
el hook devuelve error y deja el detalle en `~/nube-deploy.log`.

Para un **dominio propio** en lugar de un subdominio, usá `nd app.example.com`
en el paso 3 (requiere acme.sh instalado para el usuario; ver
[02 · Dominio y DNS](docs/02-dominio-y-dns.md#5-certificado-wildcard-para-nubeexamplecom)).

## Comandos

| Comando | Quién lo ejecuta | Qué hace |
| --- | --- | --- |
| `sudo nube-add-user <user> <email> [clave]` | root | Crea usuario, clave SSH, DB user y secretos |
| `sudo runuser -u <user> -- nd <dominio>` | root | Prepara un dominio propio y emite TLS |
| `sudo runuser -u <user> -- ns <subdominio>` | root | Prepara `<subdominio>.<base>` |
| `sudo runuser -u <user> -- nr <app> [dominio]` | root | Crea el repo bare y el hook; imprime SQL |
| `nr`, `nd`, `ns` | usuario de deploy | Igual que arriba, si ya estás como ese usuario |
| `nube-hook-post-update` | git | Hook interno de deploy |
| `nube-motd` | login | Banner del servidor |
| `create-project.sh <app> <template> <origen> [prod]` | tu máquina | Crea un proyecto y configura `origin` y `prod` |
| `make lint` | tu máquina | Valida la sintaxis de todos los scripts |

Referencia completa: [Comandos y variables](docs/referencia/comandos.md).

## Documentación

| Guía | Para qué |
| --- | --- |
| [00 · Introducción](docs/00-introduccion.md) | Servidor, VPS, hosting, dominio y DNS desde cero |
| [01 · Preparar Ubuntu](docs/01-preparar-ubuntu.md) | Crear el VPS e instalar nginx, PHP, MySQL, Node y acme.sh |
| [02 · Dominio y DNS](docs/02-dominio-y-dns.md) | Registrar el dominio, apuntarlo y configurar wildcard |
| [03 · Instalar Nube](docs/03-instalar-nube.md) | `install.sh`, `/etc/nube/nube.conf` y nginx |
| [04 · Usuarios y apps](docs/04-usuarios-y-aplicaciones.md) | Crear usuarios, dominios, repositorios y bases |
| [05 · Deploy con git](docs/05-deploy-con-git.md) | Cómo funciona el push, `.env`, Laravel, Node y rollback |
| [06 · Seguridad](docs/06-seguridad.md) | SSH, fail2ban, UFW, nginx, PHP-FPM, MySQL y secretos |
| [07 · Operación y backups](docs/07-operacion-y-backups.md) | Logs, actualizaciones, backups y restauración |
| [08 · Solución de problemas](docs/08-solucion-de-problemas.md) | Errores comunes y cómo diagnosticarlos |
| [Referencia · Arquitectura](docs/referencia/arquitectura.md) | Flujo de un request y de un deploy |
| [Referencia · Comandos](docs/referencia/comandos.md) | Scripts, variables y archivos |
| [Referencia · Plantillas](docs/referencia/plantillas.md) | `.env`, hooks propios y ejemplos |

También hay ejemplos listos para copiar en
[`docs/ejemplos/`](docs/ejemplos/): nginx, PHP-FPM por usuario, systemd para
Node y un script de backup.

## Seguridad

Nube está pensado para un VPS propio, no para revender hosting masivo sin
aislamiento adicional. Antes de publicar clientes reales:

1. Seguí la [guía de seguridad](docs/06-seguridad.md).
2. Instalá el [jail de fail2ban](fail2ban/README.md).
3. Revisá el aislamiento entre usuarios: por defecto todos los sitios corren
   con el mismo pool de PHP-FPM (`www-data`). La guía incluye un pool por
   usuario para separarlos.
4. Configurá backups y probá una restauración.

Para reportar una vulnerabilidad, leé [`SECURITY.md`](SECURITY.md).

## Alcance

Nube es deliberadamente chico y transparente:

- **PHP y Laravel** funcionan out of the box.
- **Sitios estáticos** funcionan poniendo los archivos en `public/`.
- **Node, Python, Go o Docker** se pueden correr con systemd, PM2 o Docker;
  hay recetas en [Deploy con git](docs/05-deploy-con-git.md).
- No hay panel web, ni autoescalado, ni deploy blue/green. Es un servidor
  único con scripts que podés leer y modificar.

## Créditos

Inspirado en la guía [“Guía para subir webs a Hosting o VPS”](https://blog.albo.ar/guia-para-subir-webs-a-hosting-o-vps.html)
de [albo.ar](https://albo.ar).
