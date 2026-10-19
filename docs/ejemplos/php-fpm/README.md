# PHP-FPM por usuario

Un pool por usuario aísla procesos, sesiones y archivos entre sitios. Es el
paso más importante si vas a alojar clientes distintos en el mismo VPS.

## Instalación

```bash
# Copiar el pool y ajustar user/group y rutas
sudo cp docs/ejemplos/php-fpm/juan.conf /etc/php/8.3/fpm/pool.d/juan.conf
sudo sed -i 's/\bjuan\b/NOMBRE_USUARIO/g' /etc/php/8.3/fpm/pool.d/juan.conf

sudo install -d -o NOMBRE_USUARIO -g NOMBRE_USUARIO -m 0700 /home/NOMBRE_USUARIO/tmp
sudo systemctl reload php8.3-fpm
ls -l /run/php/nube-NOMBRE_USUARIO.sock
```

En el bloque `server` de nginx de ese usuario, cambiar:

```nginx
fastcgi_pass unix:/run/php/nube-NOMBRE_USUARIO.sock;
```

## Verificación

```bash
# 1. El socket existe y es del grupo correcto
ls -l /run/php/nube-juan.sock

# 2. La app responde y escribe logs como el usuario
sudo runuser -u juan -- touch /home/juan/www/DOMINIO/storage/probe
ls -l /home/juan/www/DOMINIO/storage/probe

# 3. No puede leer otro home (con open_basedir)
sudo runuser -u juan -- cat /home/otro/secrets.gpg   # debe fallar
```

## Cuándo no usarlo

- Si todos los sitios son tuyos y confiás en el código.
- Si la app necesita leer o ejecutar fuera del home (Alpine, ImageMagick con
  binarios, integraciones con `proc_open`).
- Si preferís empezar simple: dejá `www-data` y documentá la limitación.
