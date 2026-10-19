# nginx

Configuración de nginx que instala Nube. **No es un ejemplo a copiar a mano:**
`install.sh` (y por lo tanto un `git push server main`) copia estos archivos a
`/etc/nginx/` reemplazando `#NUBE_*#` por los valores de
`/etc/nube/nube.conf`.

Para cambiar la configuración de nginx editá estos archivos y hacé push al
repositorio del servidor:

```bash
# en tu máquina
$EDITOR nginx/conf.d/nube.conf
git commit -am "nginx: ajustar rate limit"
git push server main
```

El hook verifica con `nginx -t` antes de recargar; si la configuración no
valida, **la restaura** y el push falla con el error de nginx.

## Archivos

| Archivo | Destino | Para qué |
| --- | --- | --- |
| `nginx.conf` | `/etc/nginx/nginx.conf` | Configuración principal, logs y compresión |
| `conf.d/nube.conf` | `/etc/nginx/conf.d/nube.conf` | Server blocks (HTTP, wildcard y dominios propios) |
| `snippets/nube-acme.conf` | `/etc/nginx/snippets/` | Challenge HTTP-01 de acme.sh |
| `snippets/nube-ssl.conf` | `/etc/nginx/snippets/` | Parámetros TLS |
| `snippets/nube-php-fpm.conf` | `/etc/nginx/snippets/` | Estáticos + PHP-FPM + páginas de error |
| `snippets/nube-security-headers.conf` | `/etc/nginx/snippets/` | Headers de seguridad y rate limit |
| `snippets/nube-block-scanners.conf` | `/etc/nginx/snippets/` | Bloqueo de wp-login, phpmyadmin, websql |

## Placeholders

| Placeholder | Valor |
| --- | --- |
| `#NUBE_BASE_DOMAIN#` | `NUBE_BASE_DOMAIN` |
| `#NUBE_BASE_DOMAIN_REGEX#` | `NUBE_BASE_DOMAIN` con los puntos escapados |
| `#NUBE_WEB_ROOT#` | `NUBE_WEB_ROOT` |
| `#NUBE_WEB_GROUP#` | `NUBE_WEB_GROUP` |
| `#NUBE_PHP_VERSION#` | `NUBE_PHP_VERSION` |
| `#NUBE_NGINX_SSL_DIR#` | `NUBE_NGINX_SSL_DIR` |
| `#NUBE_ACME_WEBROOT#` | `NUBE_ACME_WEBROOT` |

## Certificados

- **Wildcard** (`*.NUBE_BASE_DOMAIN`): `/etc/nginx/ssl/nube.crt` y `nube.key`.
  Lo emite `acme.sh` con DNS-01 (ver
  [02 · Dominio y DNS](../docs/02-dominio-y-dns.md)).
- **Dominios propios**: `/etc/nginx/ssl/<dominio>/fullchain.pem` y `key.pem`,
  instalados por `nube-add-domain`.
- Si todavía no hay certificado wildcard, `install.sh` deja uno autofirmado
  para que nginx pueda arrancar. Reemplazalo cuanto antes.

## Antes de recargar

1. `fastcgi_pass` usa `php<NUBE_PHP_VERSION>-fpm.sock`: si instalaste otra
   versión de PHP, cambiá `NUBE_PHP_VERSION` en `/etc/nube/nube.conf` y volvé
   a aplicar la configuración.
2. El paquete de Ubuntu deja `/etc/nginx/sites-enabled/default`; esta
   configuración **no** incluye `sites-enabled`, así que ese archivo no se usa.
   Si tenés sitios ahí, migralos a `conf.d/`.
3. Módulos como Brotli o `headers-more` no vienen en el paquete de Ubuntu: si
   los instalás, cargalos en `/etc/nginx/modules-enabled/` a mano. Este repo
   no los requiere.
