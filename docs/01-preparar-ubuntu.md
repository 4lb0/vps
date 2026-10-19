# 01 · Preparar un servidor Ubuntu

Esta guía deja un VPS Ubuntu listo para instalar Nube: nginx, PHP-FPM,
MySQL/MariaDB, Composer, Node (opcional) y acme.sh.

Tiempo estimado: **30–45 minutos**.

> Seguridad: acá se hace lo mínimo para trabajar cómodo. El endurecimiento
> completo (SSH, UFW, fail2ban, backups) está en
> [06 · Seguridad](06-seguridad.md). Hacelo antes de publicar algo real.

## 1. Crear el VPS

1. Elegí un proveedor (Hetzner, DigitalOcean, Vultr, Linode, Lightsail…).
2. Creá una instancia con **Ubuntu 24.04 LTS**, 1–2 vCPU y 2 GB de RAM.
3. Al crearla, cargá tu **clave pública SSH** (`~/.ssh/id_ed25519.pub`). Si no
   tenés una:

   ```bash
   ssh-keygen -t ed25519 -C "tu@email"
   cat ~/.ssh/id_ed25519.pub
   ```

4. Anotá la **IP pública** de la instancia.
5. Configurá el **DNS** antes de emitir certificados:
   [02 · Dominio y DNS](02-dominio-y-dns.md).

## 2. Primer acceso

La mayoría de las imágenes permiten entrar como `root`; otras crean un usuario
`ubuntu` con sudo.

```bash
# Si el proveedor te da root:
ssh root@203.0.113.10

# Si el proveedor te da un usuario (DigitalOcean, AWS…):
ssh ubuntu@203.0.113.10
```

Comprobá que estás en Ubuntu 24.04:

```bash
cat /etc/os-release
uname -a
```

## 3. Crear un usuario administrador

Si entraste como root, creá un usuario con sudo y deja de usar root:

```bash
adduser deploy
usermod -aG sudo deploy

# Copiar tu clave SSH al nuevo usuario
rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy
```

Probá la conexión **en otra terminal** antes de cerrar la actual:

```bash
ssh deploy@203.0.113.10
sudo whoami     # debe decir: root
```

Si el proveedor ya te dio un usuario con sudo, usalo como `deploy` y salteá
este paso.

## 4. Endurecer SSH (mínimo)

Desactivá contraseñas y root por SSH. El detalle y las pruebas están en
[06 · Seguridad](06-seguridad.md); acá va lo esencial:

```bash
sudo tee /etc/ssh/sshd_config.d/99-nube.conf > /dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 20
EOF

sudo sshd -t          # valida la sintaxis
sudo systemctl restart ssh
```

> No cierres la sesión actual hasta verificar en otra terminal que seguís
> entrando con la clave. Si te quedás afuera, usá la consola del proveedor.

## 5. Actualizar e instalar lo básico

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y \
    curl git unzip zip htop vim ca-certificates gnupg lsb-release \
    software-properties-common rsync

sudo timedatectl set-timezone America/Argentina/Buenos_Aires
timedatectl
```

### Swap (recomendado con 1–2 GB de RAM)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

Si el disco es pequeño, ajustá el tamaño o usá `zram`. Con 4 GB o más de RAM
podés omitir el swap.

## 6. nginx

```bash
sudo apt install -y nginx
sudo systemctl enable --now nginx
nginx -v
curl -I http://127.0.0.1     # debe responder HTTP/1.1 200 OK
```

Nginx corre como `www-data`. La configuración de Nube se instala en
[03 · Instalar Nube](03-instalar-nube.md); por ahora dejá la página por
defecto.

## 7. PHP 8.3 + extensiones

Ubuntu 24.04 trae PHP 8.3 en los repositorios oficiales.

```bash
sudo apt install -y \
    php8.3-fpm php8.3-cli php8.3-mysql php8.3-mbstring php8.3-xml \
    php8.3-curl php8.3-zip php8.3-gd php8.3-intl php8.3-bcmath \
    php8.3-opcache

sudo systemctl enable --now php8.3-fpm
php -v
php -m | sort
```

El socket que usa nginx es `/run/php/php8.3-fpm.sock`. Verificá que exista:

```bash
ls -l /run/php/
```

Si preferís otra versión (8.4, 8.2), agregá el PPA de PHP y ajustá
`NUBE_PHP_VERSION` y el `fastcgi_pass` de nginx.

### Ajuste básico de PHP

Para apps chicas alcanza con los valores por defecto. Si vas a subir archivos
grandes, editá `/etc/php/8.3/fpm/php.ini`:

```ini
upload_max_filesize = 32M
post_max_size = 32M
memory_limit = 256M
```

Y en `/etc/php/8.3/fpm/pool.d/www.conf` ajustá `pm.max_children` según la RAM
(ver [06 · Seguridad](06-seguridad.md#7-php-fpm)). Después:

```bash
sudo systemctl restart php8.3-fpm
```

## 8. MySQL o MariaDB

MariaDB suele consumir menos memoria y es 100 % compatible para este uso.
Elegí **una** de las dos opciones.

**Opción A — MariaDB:**

```bash
sudo apt install -y mariadb-server
sudo systemctl enable --now mariadb
sudo mariadb-secure-installation
```

**Opción B — MySQL 8:**

```bash
sudo apt install -y mysql-server
sudo systemctl enable --now mysql
sudo mysql_secure_installation
```

En ambos casos verificá que solo escuche local:

```bash
sudo ss -tlnp | grep 3306
# tcp  0  0 127.0.0.1:3306  ...   <- no debe decir 0.0.0.0:3306
mysql --version
```

Si `mysqladmin ping` no responde, revisá
`sudo journalctl -u mariadb -n 50` (o `-u mysql`).

## 9. Composer

```bash
curl -sS https://getcomposer.org/installer \
  | php -- --install-dir=/usr/local/bin --filename=composer
composer -V
```

El hook de deploy ejecuta `composer` en cada push, así que tiene que estar en
el PATH del usuario de deploy (instalado en `/usr/local/bin`).

## 10. Node.js y Python (opcional)

### Node.js

Solo si vas a correr apps Node, bundlers (`vite`, `npm run build`) o el
frontend de Laravel.

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
sudo -E bash /tmp/nodesource_setup.sh
sudo apt install -y nodejs
node -v
npm -v
```

Si usás PM2 para mantener vivo el proceso:

```bash
sudo npm install -g pm2
sudo runuser -u nube -- pm2 startup systemd -u nube --hp /home/nube
# pm2 imprime un comando sudo: ejecutalo
```

### Python

Solo si vas a correr apps Python. El hook crea el entorno virtual, así que
hace falta `venv`:

```bash
sudo apt install -y python3 python3-venv python3-pip
python3 -V
```

## 11. acme.sh para certificados

```bash
curl https://get.acme.sh | sudo sh -s email=admin@example.com
sudo /root/.acme.sh/acme.sh --version
```

Instala acme.sh en `/root/.acme.sh` y agrega un cron para renovar. En
`/etc/nube/nube.conf` se configura con:

```sh
NUBE_ACME_HOME="/root/.acme.sh"
NUBE_ACME_MODE="webroot"     # HTTP-01
```

Para un certificado **wildcard** hace falta DNS-01; se explica en
[02 · Dominio y DNS](02-dominio-y-dns.md).

## 12. Directorios y permisos

Nube publica los sitios en `/var/www/<dominio>` (symlinks al home del usuario
de deploy). Para que el usuario pueda crear sus enlaces, `/var/www` debe ser
escribible por el grupo `www-data`:

```bash
sudo chgrp www-data /var/www
sudo chmod 2775 /var/www

# Webroot compartido para el challenge HTTP-01 de acme.sh
sudo install -d -o www-data -g www-data -m 2775 /var/www/acme

# Destino de los certificados emitidos por nd
sudo install -d -o root -g www-data -m 2770 /etc/nginx/ssl

ls -ld /var/www /var/www/acme /etc/nginx/ssl
```

`install.sh` (y por lo tanto `bootstrap.sh`) también ajusta estas tres rutas.

El bit `2` (setgid) hace que los archivos nuevos hereden el grupo del
directorio (`www-data` en los dos primeros casos).

## 13. Firewall (adelanto)

```bash
sudo apt install -y ufw
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

La configuración completa, incluido fail2ban, está en
[06 · Seguridad](06-seguridad.md).

## 14. Verificación

```bash
echo "--- versiones ---"
nginx -v
php -v | head -1
composer -V
mysql --version
node -v || true
python3 -V || true
acme.sh --version || sudo /root/.acme.sh/acme.sh --version | head -2

echo "--- servicios ---"
systemctl is-active nginx php8.3-fpm
systemctl is-active mariadb 2>/dev/null || systemctl is-active mysql

echo "--- red ---"
sudo ss -tlnp | grep -E ':(80|443|3306)'
```

## Checklist

- [ ] VPS Ubuntu 24.04 con clave SSH cargada.
- [ ] Usuario con sudo (no root) y contraseñas deshabilitadas.
- [ ] Dominio apuntando al servidor (ver [02](02-dominio-y-dns.md)).
- [ ] nginx activo.
- [ ] PHP 8.3-FPM activo y con socket.
- [ ] MySQL/MariaDB activo y escuchando solo en `127.0.0.1`.
- [ ] Composer disponible globalmente.
- [ ] Node.js y/o Python instalados si vas a usarlos.
- [ ] acme.sh instalado.
- [ ] `/var/www` con setgid y grupo `www-data`.
- [ ] UFW permitiendo 22, 80 y 443.

Siguiente: [02 · Dominio y DNS](02-dominio-y-dns.md).
