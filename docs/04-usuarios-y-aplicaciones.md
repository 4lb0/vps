# 04 · Usuarios y apps

Nube organiza todo por **usuario de deploy**. Cada usuario puede tener varias
apps, cada app un repositorio y un sitio, y todos los usuarios comparten el
mismo nginx, PHP-FPM y MySQL.

## 1. Modelo

```text
usuario juan (sin shell, git-shell)
├── ~/git/blog.git              repositorio bare de la app "blog"
├── ~/git/tienda.git            repositorio bare de la app "tienda"
├── ~/www/blog.example.com/     app "blog"
│   └── public/                 lo que sirve nginx
├── ~/www/tienda.example.com/   app "tienda"
│   └── public/
├── ~/.ssh/authorized_keys      claves que pueden hacer push
├── ~/secrets.gpg               NUBE_DB_USER y NUBE_DB_PASS cifrados
└── ~/nube-deploy.log           salida de cada deploy
```

En `/var/www/<dominio>` hay un symlink a `~/www/<dominio>` para que nginx
tenga una ruta estable:

```text
/var/www/blog.example.com -> /home/juan/www/blog.example.com
```

La base de datos de cada app se llama igual que el dominio, con los puntos y
guiones convertidos en guiones bajos: `blog.example.com` →
`blog_example_com`.

## 2. Crear un usuario

```bash
sudo nube-add-user juan juan@example.com "ssh-ed25519 AAAA... juan@laptop"
```

También funciona `sudo add-user.sh ...` (mismo script).

Qué hace:

1. Crea el usuario `juan` con `git-shell` (no puede abrir una shell).
2. Lo agrega al grupo `www-data`.
3. Crea un usuario de MySQL `juan_<aleatorio>` con contraseña aleatoria.
4. Genera una clave GPG sin passphrase para `juan@example.com`.
5. Guarda `NUBE_DB_USER` y `NUBE_DB_PASS` cifrados en `~/secrets.gpg`.
6. Instala la clave pública en `~/.ssh/authorized_keys`.
7. Genera una clave `id_ed25519` de deploy (por si necesita clonar
   dependencias privadas).
8. Configura `~/git-shell-commands/no-interactive-login`.

Si no pasás la clave pública, el usuario igual se crea. Agregala después:

```bash
sudo install -d -o juan -g juan -m 0700 /home/juan/.ssh
echo "ssh-ed25519 AAAA... juan@laptop" | sudo tee -a /home/juan/.ssh/authorized_keys
sudo chown juan:juan /home/juan/.ssh/authorized_keys
```

### Probar el acceso

```bash
ssh juan@nube.example.com
```

No vas a ver una shell: el `no-interactive-login` te muestra el mensaje y
cierra la sesión. Eso es correcto. Si querés comprobar que las claves de git
funcionan:

```bash
ssh -T juan@nube.example.com
```

## 3. Crear una app en un subdominio

Ideal para prototipos: no hace falta tocar DNS ni emitir certificados (el
wildcard y `nube.conf` ya cubren `*.nube.example.com`).

```bash
sudo runuser -u juan -- ns blog
```

Crea `/home/juan/www/blog.nube.example.com/public` y lo deja listo para
recibir el push.

Si estás logueado directamente como el usuario, alcanza con `ns blog`.

## 4. Crear una app en un dominio propio

```bash
sudo runuser -u juan -- nd blog.example.com
```

Además de crear el directorio, emite el certificado con acme.sh
(según `NUBE_ACME_MODE`). Requiere:

- que `blog.example.com` ya resuelva al VPS;
- que el usuario tenga acme.sh instalado (`~/.acme.sh/acme.sh`);
- que el challenge HTTP-01 llegue a nginx (`/var/www/acme`).

Si el certificado no se emite, el sitio queda creado igual; corregí el DNS y
volvé a ejecutar `nd`.

## 5. Crear el repositorio y la base

```bash
sudo runuser -u juan -- nr blog blog.example.com | sudo mysql
```

`nr`:

1. crea `~/git/blog.git` (bare) si no existe;
2. escribe `hooks/post-update` apuntando a `nube-hook-post-update`;
3. asegura el directorio web y el symlink;
4. imprime por stdout el SQL y los mensajes por stderr.

El SQL que genera es:

```sql
CREATE DATABASE IF NOT EXISTS `blog_example_com`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON `blog_example_com`.*
  TO 'juan_a1b2c3d4e5f6'@'127.0.0.1';
FLUSH PRIVILEGES;
```

Si el pipe a `mysql` falla, revisá que estés usando `sudo mysql` (root por
socket) y que MySQL esté corriendo.

Para ver el SQL sin ejecutarlo:

```bash
sudo runuser -u juan -- nr blog blog.example.com
```

## 6. Varias apps por usuario

No hay límite: repetí `ns`/`nd` y `nr` con otro nombre. Todas las apps del
usuario comparten `secrets.gpg`, que contiene **un** usuario de MySQL. Cada
app tiene su propia base y el `GRANT` correspondiente.

```bash
sudo runuser -u juan -- ns tienda
sudo runuser -u juan -- nr tienda tienda.nube.example.com | sudo mysql
```

Orden recomendado: `ns`/`nd` primero (crea el directorio) y `nr` después
(crea el repo y la base). `nr` también asegura el directorio, así que si
omites `ns`/`nd` el sitio se crea, pero no vas a tener el mensaje de TLS.

## 7. Permisos y aislamiento

| Recurso | Quién puede leer/escribir |
| --- | --- |
| `~/www/<dominio>` | El dueño y el grupo `www-data` |
| `~/secrets.gpg` | Solo el dueño |
| `~/git/<app>.git` | El dueño (los demás usuarios del grupo no deberían, pero el aislamiento no es perfecto) |
| Base de datos de otra app | No (usuario MySQL distinto) |

**Importante:** por defecto todos los sitios de todos los usuarios corren con
el mismo pool de PHP-FPM (`www-data`). Un bug en la app de un usuario podría
leer archivos de otro que sean legibles por el grupo. Si vas a alojar clientes
distintos, configurá un
[pool de PHP-FPM por usuario](06-seguridad.md#7-php-fpm-por-usuario). Para
proyectos propios, el modelo alcanza.

## 8. Eliminar una app

No hay comando automático a propósito: borrar es irreversible. Pasos:

```bash
# 1. Backup primero
sudo mysqldump blog_example_com > /root/blog_example_com.sql
sudo tar czf /root/blog-example-com.tar.gz -C /home/juan/www blog.example.com

# 2. Quitar el sitio
sudo rm -rf /home/juan/www/blog.example.com
sudo rm -f /var/www/blog.example.com

# 3. Quitar el repositorio
sudo rm -rf /home/juan/git/blog.git

# 4. Quitar la base y el GRANT (opcional)
sudo mysql -e "DROP DATABASE blog_example_com;"
```

## 9. Eliminar un usuario

```bash
# Backup de sus datos y bases primero
sudo tar czf /root/juan-home.tar.gz /home/juan
sudo mysqldump --all-databases > /root/all-databases-$(date +%F).sql

# Borrar usuario y home (incluye claves y secretos)
sudo userdel --remove juan

# Borrar sus bases y su usuario de MySQL
sudo mysql -e "SELECT schema_name FROM information_schema.schemata;"  # identificar
sudo mysql -e "DROP DATABASE ...; DROP USER 'juan_a1b2c3d4e5f6'@'127.0.0.1';"

# Quitar symlinks huerfanos
ls -l /var/www | grep juan
```

## 10. Cambiar credenciales de base

Si se filtró una contraseña, rotala:

```bash
NEW_PASS="$(openssl rand -base64 32)"
sudo mysql -e "ALTER USER 'juan_a1b2c3d4e5f6'@'127.0.0.1' IDENTIFIED BY '$NEW_PASS';"

# Actualizar secrets.gpg del usuario
sudo runuser -u juan -- env HOME=/home/juan bash -c \
  "printf 'export NUBE_DB_USER=%q\nexport NUBE_DB_PASS=%q\n' \
   juan_a1b2c3d4e5f6 '$NEW_PASS' \
   | gpg --batch --yes --quiet --encrypt -r juan@example.com -o /home/juan/secrets.gpg"
```

Después hacé un push para que el `.env` de cada app se actualice.

## Checklist

- [ ] Usuario creado y con acceso SSH verificado.
- [ ] `ns` o `nd` ejecutado según el tipo de dominio.
- [ ] `nr ... | sudo mysql` sin errores.
- [ ] `git remote add prod` configurado en tu máquina.
- [ ] Primer push hecho ([05](05-deploy-con-git.md)).
- [ ] Si vas a hostear terceros: pool de PHP-FPM por usuario.

Siguiente: [05 · Deploy con git](05-deploy-con-git.md).
