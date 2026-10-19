# 04 · El usuario y las apps

Nube usa **un solo usuario de deploy** (`NUBE_USER`, por defecto `nube`). Ese
usuario es dueño de todos los repositorios y de todos los sitios; cada app
tiene su repositorio, su dominio y su base de datos.

## 1. Modelo

```text
usuario nube (git-shell, sin shell interactivo)
├── git/nube.git                repositorio del servidor (aplica la config)
├── git/blog.git                repositorio bare de la app "blog"
├── git/tienda.git              repositorio bare de la app "tienda"
├── www/blog.example.com/       app "blog"
│   └── public/                 lo que sirve nginx
├── www/tienda.example.com/     app "tienda"
│   └── public/
├── .ssh/authorized_keys        claves que pueden hacer push
├── secrets.gpg                 NUBE_DB_USER y NUBE_DB_PASS cifrados
└── nube-deploy.log             salida de cada deploy
```

En `/var/www/<dominio>` hay un symlink a `~/www/<dominio>` para que nginx
tenga una ruta estable:

```text
/var/www/blog.example.com -> /home/nube/www/blog.example.com
```

La base de datos de cada app se llama igual que el dominio, con los puntos y
guiones convertidos en guiones bajos: `blog.example.com` →
`blog_example_com`.

## 2. El usuario de deploy

Lo crea `bootstrap.sh`. Si querés crearlo (o reinstalar su clave SSH) aparte:

```bash
sudo nube-init-user --ssh-key-file ~/.ssh/id_ed25519.pub
```

Qué hace:

1. Crea el usuario `nube` con `git-shell` (no puede abrir una shell), según
   `NUBE_USER` de `/etc/nube/nube.conf`.
2. Lo agrega a los grupos `www-data` y `nube`.
3. Crea un usuario de MySQL `nube_<aleatorio>` con contraseña aleatoria.
4. Genera una clave GPG sin passphrase para `NUBE_USER_MAIL`.
5. Guarda `NUBE_DB_USER` y `NUBE_DB_PASS` cifrados en `~/secrets.gpg`.
6. Instala la clave pública en `~/.ssh/authorized_keys`.
7. Genera una clave `id_ed25519` de deploy (por si necesita clonar
   dependencias privadas).
8. Configura `~/git-shell-commands/no-interactive-login`.

Si el usuario ya existe, el comando no lo toca: solo agrega la clave SSH si la
pasaste.

Si no pasás la clave al crearlo, agregala después:

```bash
sudo install -d -o nube -g nube -m 0700 /home/nube/.ssh
echo "ssh-ed25519 AAAA... yo@laptop" | sudo tee -a /home/nube/.ssh/authorized_keys
sudo chown nube:nube /home/nube/.ssh/authorized_keys
```

### Probar el acceso

```bash
ssh nube@nube.example.com
```

No vas a ver una shell: el `no-interactive-login` te muestra el mensaje y
cierra la sesión. Eso es correcto. Si querés comprobar que las claves de git
funcionan:

```bash
ssh -T nube@nube.example.com
```

## 3. Crear una app en un subdominio

Ideal para prototipos: no hace falta tocar DNS ni emitir certificados (el
wildcard y `conf.d/nube.conf` ya cubren `*.nube.example.com`).

```bash
sudo runuser -u nube -- nube-add-subdomain blog
```

Crea `/home/nube/www/blog.nube.example.com/public` y lo deja listo para
recibir el push.

Si estás logueado directamente como el usuario, alcanza con
`nube-add-subdomain blog` (el usuario tiene `git-shell`, así que en la práctica
se corre con `runuser`).

## 4. Crear una app en un dominio propio

```bash
sudo runuser -u nube -- nube-add-domain blog.example.com
```

Además de crear el directorio, emite el certificado con acme.sh
(según `NUBE_ACME_MODE`). Requiere:

- que `blog.example.com` ya resuelva al VPS;
- que el usuario tenga acme.sh instalado (`~/.acme.sh/acme.sh`);
- que el challenge HTTP-01 llegue a nginx (`/var/www/acme`).

Si el certificado no se emite, el sitio queda creado igual; corregí el DNS y
volvé a ejecutar `nube-add-domain`.

## 5. Crear el repositorio y la base

```bash
sudo runuser -u nube -- nube-add-repository blog blog.example.com | sudo mysql
```

`nube-add-repository`:

1. crea `~/git/blog.git` (bare) si no existe;
2. escribe `hooks/post-update` apuntando a `nube-hook-post-update`;
3. asegura el directorio web y el symlink;
4. imprime por stdout el SQL y los mensajes por stderr.

El SQL que genera es:

```sql
CREATE DATABASE IF NOT EXISTS `blog_example_com`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON `blog_example_com`.*
  TO 'nube_a1b2c3d4e5f6'@'127.0.0.1';
FLUSH PRIVILEGES;
```

Si el pipe a `mysql` falla, revisá que estés usando `sudo mysql` (root por
socket) y que MySQL esté corriendo.

Para ver el SQL sin ejecutarlo:

```bash
sudo runuser -u nube -- nube-add-repository blog blog.example.com
```

## 6. Varias apps

No hay límite: repetí `nube-add-subdomain`/`nube-add-domain` y
`nube-add-repository` con otro nombre. Todas las apps comparten
`secrets.gpg`, que contiene **un** usuario de MySQL. Cada app tiene su propia
base y el `GRANT` correspondiente.

```bash
sudo runuser -u nube -- nube-add-subdomain tienda
sudo runuser -u nube -- nube-add-repository tienda tienda.nube.example.com | sudo mysql
```

Orden recomendado: `nube-add-subdomain`/`nube-add-domain` primero (crea el
directorio) y `nube-add-repository` después (crea el repo y la base).
`nube-add-repository` también asegura el directorio, así que si omites
`nube-add-subdomain`/`nube-add-domain` el sitio se crea, pero no vas a tener el
mensaje de TLS.

> Ojo: `nube` está reservado para el repositorio del servidor
> (`~/git/nube.git`). No lo uses como nombre de app.

## 7. Permisos

| Recurso | Quién puede leer/escribir |
| --- | --- |
| `~/www/<dominio>` | El usuario de deploy y el grupo `www-data` |
| `~/secrets.gpg` | Solo el usuario de deploy |
| `~/git/<app>.git` | Solo el usuario de deploy |
| Base de datos de cada app | El usuario de MySQL de la app |

Los sitios corren con el pool de PHP-FPM de `www-data`. Como hay un solo
usuario de deploy, no hay separación entre tus propios proyectos: es todo
código tuyo. Si necesitás alojar clientes que no confían entre sí, usá un VPS
por cliente (ver [06 · Seguridad](06-seguridad.md)).

## 8. Eliminar una app

No hay comando automático a propósito: borrar es irreversible. Pasos:

```bash
# 1. Backup primero
sudo mysqldump blog_example_com > /root/blog_example_com.sql
sudo tar czf /root/blog-example-com.tar.gz -C /home/nube/www blog.example.com

# 2. Quitar el sitio
sudo rm -rf /home/nube/www/blog.example.com
sudo rm -f /var/www/blog.example.com

# 3. Quitar el repositorio
sudo rm -rf /home/nube/git/blog.git

# 4. Quitar la base y el GRANT (opcional)
sudo mysql -e "DROP DATABASE blog_example_com;"
```

## 9. Cambiar credenciales de base

Si se filtró la contraseña, rotala:

```bash
NEW_PASS="$(openssl rand -base64 32)"
sudo mysql -e "ALTER USER 'nube_a1b2c3d4e5f6'@'127.0.0.1' IDENTIFIED BY '$NEW_PASS';"

# Actualizar secrets.gpg del usuario
sudo runuser -u nube -- env HOME=/home/nube bash -c \
  "printf 'export NUBE_DB_USER=%q\nexport NUBE_DB_PASS=%q\n' \
   nube_a1b2c3d4e5f6 '$NEW_PASS' \
   | gpg --batch --yes --quiet --encrypt -r nube@example.com -o /home/nube/secrets.gpg"
```

Después hacé un push para que el `.env` de cada app se actualice.

## Checklist

- [ ] Usuario de deploy creado y con acceso SSH verificado.
- [ ] `nube-add-subdomain` o `nube-add-domain` ejecutado según el tipo de dominio.
- [ ] `nube-add-repository ... | sudo mysql` sin errores.
- [ ] `git remote add prod` configurado en tu máquina.
- [ ] Primer push hecho ([05](05-deploy-con-git.md)).

Siguiente: [05 · Deploy con git](05-deploy-con-git.md).
