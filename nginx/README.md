# nginx

Configuración del servidor original (`nube.pragmore.com`). Muchos archivos de
este directorio son específicos de ese servidor; para una instalación nueva
usá la configuración genérica de
[`docs/ejemplos/nginx/`](../docs/ejemplos/nginx/), que incluye TLS, rate limit
y headers de seguridad.

## Archivos

### Reutilizables

| Archivo | Para qué |
| --- | --- |
| `nginx.conf` | Configuración principal (log format `main`, `server_tokens off`, includes) |
| `default.d/server.conf` | `try_files` + PHP-FPM para cada sitio |
| `default.d/prevent-attacks.conf` | Bloquea `wp-login`, `phpmyadmin`, etc. |
| `default.d/ssl.conf` | Certificado por `$ssl_server_name` desde `~/.acme.sh` |
| `ssl` | Parámetros TLS (protocolos, ciphers, sesiones) |
| `fastcgi.conf` | Parámetros FastCGI usados por PHP-FPM |
| `mime.types` | Tipos MIME |
| `conf.d/gzip.conf` | Compresión gzip |
| `conf.d/brotli.conf` | Compresión Brotli (requiere módulo) |
| `modules/*.conf` | Carga de módulos dinámicos (brotli, headers-more) |

### Específicos de `nube.pragmore.com`

Estos archivos **no** sirven para otra instalación sin editar:

| Archivo | Qué tiene |
| --- | --- |
| `conf.d/deploymy.site.conf` | Redirect de un dominio propio a `nube.pragmore.com` |
| `conf.d/domains-sale.conf` | Dominios en venta de Pragmore |
| `conf.d/reduceurl_redirects.conf` | Sitio `reduceurl.com` (`kv.ar`, `now.ar`) |

Si no los necesitás, borralos antes de copiar `conf.d/` a tu servidor.

## Instalación

Seguí [`docs/03-instalar-nube.md`](../docs/03-instalar-nube.md). Resumen:

```bash
sudo cp nginx/nginx.conf /etc/nginx/nginx.conf
sudo cp -r nginx/default.d /etc/nginx/
sudo cp nginx/ssl /etc/nginx/ssl.conf
sudo cp nginx/fastcgi.conf /etc/nginx/fastcgi.conf
# Solo los que uses:
sudo cp nginx/conf.d/gzip.conf /etc/nginx/conf.d/
sudo nginx -t && sudo systemctl reload nginx
```

## Diferencias con los ejemplos

- Estos archivos emiten/leen certificados desde `~/.acme.sh` con
  `--stateless`; los ejemplos usan `--install-cert` a `/etc/nginx/ssl`.
- El `fastcgi_pass` está fijado a `php8.1-fpm.sock`; ajustalo a tu versión.
- Los ejemplos agregan headers de seguridad, rate limit y TLS moderno.
- El `log_format main` incluye `$host` al inicio; el filtro de fail2ban
  [`nginx-nube-scan`](../fail2ban/filter.d/nginx-nube-scan.conf) asume esa
  forma (o la de `nginx.conf` en los ejemplos).
