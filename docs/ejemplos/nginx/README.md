# Ejemplos de nginx

Configuración de referencia para un servidor Nube, probada sobre Ubuntu 24.04
(nginx 1.24). Ver la explicación en
[`docs/03-instalar-nube.md`](../../03-instalar-nube.md) y
[`docs/06-seguridad.md`](../../06-seguridad.md).

## Archivos

```text
nginx.conf                              -> /etc/nginx/nginx.conf
nube.conf                               -> /etc/nginx/conf.d/nube.conf
snippets/nube-acme.conf                 -> /etc/nginx/snippets/nube-acme.conf
snippets/nube-ssl.conf                  -> /etc/nginx/snippets/nube-ssl.conf
snippets/nube-security-headers.conf     -> /etc/nginx/snippets/nube-security-headers.conf
snippets/nube-php-fpm.conf              -> /etc/nginx/snippets/nube-php-fpm.conf
```

## Instalación

```bash
cd /opt/nube   # o donde hayas clonado el repo

sudo install -d /etc/nginx/snippets
sudo cp docs/ejemplos/nginx/nginx.conf /etc/nginx/nginx.conf
sudo cp docs/ejemplos/nginx/nube.conf  /etc/nginx/conf.d/nube.conf
sudo cp docs/ejemplos/nginx/snippets/*.conf /etc/nginx/snippets/

# Editar el dominio base
sudo sed -i 's/nube\.example\.com/TU-DOMINIO-BASE/g' \
  /etc/nginx/nginx.conf /etc/nginx/conf.d/nube.conf

sudo nginx -t
sudo systemctl reload nginx
```

Si tu `/etc/nginx/nginx.conf` de Ubuntu incluye `sites-enabled/*`, quitá el
bloque `default_server` de `/etc/nginx/sites-enabled/default` o borralo, para
no chocar con `nube.conf`.

## Cosas a revisar

- `fastcgi_pass unix:/run/php/php8.3-fpm.sock` en
  `snippets/nube-php-fpm.conf`: ajustá la versión de PHP.
- `ssl_certificate /etc/nginx/ssl/nube.crt`: es el certificado **wildcard**
  `*.nube.example.com` (ver [02 · Dominio y DNS](../../02-dominio-y-dns.md)).
- El bloque catch-all usa `/etc/nginx/ssl/$ssl_server_name/`, donde `nd`
  instala el certificado de cada dominio propio.
- `limit_req` y `limit_conn` requieren las zonas definidas en `nginx.conf`.
- HSTS está comentado: activalo solo cuando todo el dominio funcione por
  HTTPS.
