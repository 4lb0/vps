# Plantillas

Recetas listas para copiar. El detalle está en
[05 · Deploy con git](../05-deploy-con-git.md).

## Placeholders de `.env`

El hook reemplaza estos valores en tu `.env` (o en `.env.example` la primera
vez):

| Placeholder | Valor |
| --- | --- |
| `#NUBE_ROOT#` | `/var/www/<dominio>` |
| `#NUBE_URL#` | `https://<dominio>` |
| `#NUBE_DB_CONN#` | `mysql` |
| `#NUBE_DB_HOST#` | `127.0.0.1` |
| `#NUBE_DB_PORT#` | `3306` |
| `#NUBE_DB_NAME#` | Base de la app (`blog_example_com`) |
| `#NUBE_DB_USER#` | Usuario de MySQL del dueño |
| `#NUBE_DB_PASS#` | Contraseña de MySQL |

Archivos completos:

- [`../ejemplos/env/laravel.env.example`](../ejemplos/env/laravel.env.example)
- [`../ejemplos/env/generic.env.example`](../ejemplos/env/generic.env.example)

## Estructura mínima de un repo

### Estático

```text
public/
├── index.html
└── assets/app.css
```

### Laravel

```text
app/ bootstrap/ config/ database/ public/ routes/ storage/ vendor (no)
.env.example
composer.json
artisan
```

`vendor/` no se versiona: el hook corre `composer install`.

### PHP propio

```text
public/
├── index.php
└── api.php
src/
composer.json        # opcional
```

## Hook propio `.nube/deploy`

```bash
mkdir -p .nube
cat > .nube/deploy <<'EOF'
#!/bin/bash
set -euo pipefail
cd "$NUBE_PATH"

# Migraciones sin interactividad
php artisan migrate --force --no-interaction

# Cachear
php artisan config:cache
php artisan route:cache
php artisan view:cache
EOF
chmod +x .nube/deploy
```

## Recetas

### Static con build

```bash
#!/bin/bash
# .nube/deploy
set -euo pipefail
cd "$NUBE_PATH"
npm ci
npm run build
rsync -a --delete dist/ public/
```

### Node con PM2

Ver [`../ejemplos/deploy/node-deploy.sh`](../ejemplos/deploy/node-deploy.sh) y
[`../ejemplos/systemd/`](../ejemplos/systemd/).

### Laravel con workers

```bash
#!/bin/bash
# .nube/deploy
set -euo pipefail
cd "$NUBE_PATH"
php artisan storage:link || true
php artisan queue:restart || true
```

### Python (Gunicorn) con systemd

```ini
# /etc/systemd/system/blog.service
[Unit]
Description=blog (Nube)
After=network.target

[Service]
User=nube
WorkingDirectory=/home/nube/www/blog.example.com
ExecStart=/home/nube/www/blog.example.com/.venv/bin/gunicorn app:app -b 127.0.0.1:8000
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
#!/bin/bash
# .nube/deploy
set -euo pipefail
cd "$NUBE_PATH"
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
sudo systemctl restart blog    # requiere una regla en sudoers
```

## Plantilla de nginx para un dominio propio

Sin PHP, solo estáticos:

```nginx
server {
    listen 443 ssl http2;
    server_name app.example.com;

    root /var/www/app.example.com/public;
    index index.html;

    ssl_certificate     /etc/nginx/ssl/app.example.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/app.example.com/key.pem;

    include /etc/nginx/snippets/nube-ssl.conf;
    include /etc/nginx/snippets/nube-security-headers.conf;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Con proxy a Node:

```nginx
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## systemd para un worker de Laravel

```ini
# /etc/systemd/system/blog-worker.service
[Unit]
Description=blog queue worker
After=network.target mysql.service

[Service]
User=nube
WorkingDirectory=/home/nube/www/blog.example.com
ExecStart=/usr/bin/php artisan queue:work --sleep=3 --tries=3 --max-time=3600
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now blog-worker
```
