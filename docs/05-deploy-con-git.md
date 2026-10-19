# 05 · Deploy con git

Así funciona el flujo que hace Nube: un `git push` actualiza el código,
instala dependencias y deja la app publicada.

## 1. Configurar el remoto

Desde la carpeta de tu proyecto:

```bash
git init                        # si todavía no es un repo
git add .
git commit -m "primer commit"

git remote add prod juan@nube.example.com:git/blog
git push prod main
```

La ruta `juan@host:git/blog` es el repositorio bare `~/git/blog.git` del
usuario. También podés usar la forma explícita:

```bash
git remote add prod ssh://juan@nube.example.com/home/juan/git/blog.git
```

Para no escribir `prod` cada vez:

```bash
git push prod main
git push prod main --tags      # si usas tags para releases
```

### Primera vez

Si es la primera vez que te conectás, git te pide confirmar la huella del
servidor. Aceptala (`yes`) y quedará en `~/.ssh/known_hosts`.

## 2. Qué pasa en el servidor

```text
git push prod main
      │
      ▼
sshd ── git-shell ── git-receive-pack
      │
      ▼
~/git/blog.git recibe los objetos
      │
      ▼
hooks/post-update  →  nube-hook-post-update refs/heads/main blog.example.com ~/git/blog.git
      │
      ├─ 1. checkout en /var/www/blog.example.com
      ├─ 2. prepara .env (plantilla + #NUBE_*#)
      ├─ 3. composer install (si hay composer.json)
      ├─ 4. Laravel: APP_KEY, permisos, caches, migraciones
      └─ 5. .nube/deploy (si existe y es ejecutable)
      │
      ▼
https://blog.example.com
```

El hook imprime el progreso en tu terminal:

```text
☁️  Nube - https://blog.example.com 🚀
Haciendo el deploy a blog.example.com
ref: refs/heads/main
nube: actualizando archivos
nube: preparando .env
Framework encontrado: Laravel
Cacheando configuracion... ok
Corriendo migraciones...
Listo → https://blog.example.com
Log: /home/juan/nube-deploy.log
```

Si un paso falla, el push termina con error y el detalle queda en
`~/nube-deploy.log`.

## 3. `.env` y plantillas

El hook reemplaza placeholders en tu `.env`. En el repo versioná
`.env.example` con placeholders, **nunca** el `.env` con secretos:

```dotenv
APP_NAME=Blog
APP_URL=#NUBE_URL#

DB_CONNECTION=#NUBE_DB_CONN#
DB_HOST=#NUBE_DB_HOST#
DB_PORT=#NUBE_DB_PORT#
DB_DATABASE=#NUBE_DB_NAME#
DB_USERNAME=#NUBE_DB_USER#
DB_PASSWORD=#NUBE_DB_PASS#
```

| Placeholder | Se reemplaza por |
| --- | --- |
| `#NUBE_ROOT#` | `/var/www/<dominio>` (raíz del proyecto) |
| `#NUBE_URL#` | `https://<dominio>` |
| `#NUBE_DB_CONN#` | `mysql` |
| `#NUBE_DB_HOST#` | `127.0.0.1` |
| `#NUBE_DB_PORT#` | `3306` |
| `#NUBE_DB_NAME#` | Nombre de la base (`blog_example_com`) |
| `#NUBE_DB_USER#` | Usuario de MySQL del dueño |
| `#NUBE_DB_PASS#` | Contraseña de MySQL |

Reglas del hook:

- Si no hay `.env` pero sí `.env.example`, lo copia.
- Reemplaza los placeholders en cada deploy.
- **No pisa** variables que no sean placeholders: tus `MAIL_*`, `API_KEY`, etc.
  quedan como estén en el `.env` del servidor.
- En Laravel además fuerza `APP_URL` y `DB_*`.

Para secretos que no querés versionar, agregalos a mano en el `.env` del
servidor:

```bash
sudo runuser -u juan -- bash -c 'cat >> /home/juan/www/blog.example.com/.env' <<'EOF'
MAIL_PASSWORD=...
EOF
```

## 4. Laravel

Si el repo tiene `artisan`, el hook ejecuta:

| Paso | Comando |
| --- | --- |
| `.env` | Fuerza `APP_URL`, `DB_*` |
| `APP_KEY` | `php artisan key:generate --force` si falta |
| Permisos | `chgrp -R www-data storage bootstrap/cache` y `chmod -R g+rwX` |
| Cache | `php artisan config:cache`, `route:cache`, `view:cache` |
| Migraciones | `php artisan migrate --force` |

Comandos útiles para saltarte pasos en un deploy puntual:

```bash
NUBE_SKIP_ARTISAN_CACHE=1 git push prod main
NUBE_SKIP_MIGRATIONS=1 git push prod main
NUBE_SKIP_COMPOSER=1 git push prod main
```

No funcionan como variables de entorno del `git push` (se ejecutan en el
servidor). Para eso, usá un hook propio (paso 7) o hacé el cambio en el
servidor.

### Si `route:cache` falla

Es normal con rutas que usan closures. Desactivá el cacheo de rutas con un
[hook propio](#7-hook-propio-de-la-app) o corregí las rutas.

## 5. Sitios estáticos

Poné los archivos que querés publicar dentro de `public/`:

```text
mi-sitio/
├── public/
│   ├── index.html
│   ├── style.css
│   └── assets/...
└── README.md
```

Nginx sirve `public/` directamente. No hace falta PHP, MySQL ni Composer.
Si el sitio ya está "compilado" (por ejemplo un build de Vite o Eleventy),
commiteá el resultado en `public/` o compilalo en un hook propio.

## 6. Node, Python y otros lenguajes

Nginx solo sirve archivos y PHP. Un proceso Node/Python/Go necesita un
servicio que lo mantenga vivo, y nginx actuando como proxy inverso.

Receta con **PM2**, que corre como el usuario de deploy:

```bash
# En el servidor, como el usuario juan
sudo runuser -u juan -- npm install -g pm2
sudo runuser -u juan -- pm2 startup systemd -u juan --hp /home/juan
# pm2 imprime un comando sudo; ejecutalo
```

Tu repo incluye `ecosystem.config.js` y `.nube/deploy`:

```js
// ecosystem.config.js
module.exports = {
  apps: [{
    name: "blog",
    script: "server.js",
    cwd: "/home/juan/www/blog.example.com",
    env: { PORT: 3000, NODE_ENV: "production" }
  }]
};
```

```bash
#!/bin/bash
# .nube/deploy
set -euo pipefail
cd "$NUBE_PATH"
npm ci --omit=dev
npm run build --if-present
pm2 startOrReload ecosystem.config.js
pm2 save
```

Y en nginx, reemplazá `include .../nube-php-fpm.conf;` por un proxy:

```nginx
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Hay un ejemplo completo en
[`docs/ejemplos/systemd/`](ejemplos/systemd/) y
[`docs/ejemplos/deploy/`](ejemplos/deploy/). Para Python/Go, el mismo patrón:
`gunicorn`/binario en systemd + proxy en nginx.

## 7. Hook propio de la app

Para pasos propios (build, workers, cache, links), creá `.nube/deploy`
ejecutable en el repo:

```bash
mkdir -p .nube
cat > .nube/deploy <<'EOF'
#!/bin/bash
set -euo pipefail
cd "$NUBE_PATH"
php artisan storage:link || true
php artisan queue:restart || true
EOF
chmod +x .nube/deploy
git add .nube/deploy
```

Se ejecuta al final del deploy, como el usuario, con estas variables:
`NUBE_DOMAIN`, `NUBE_PATH`, `NUBE_URL`, `NUBE_REFS`, `NUBE_DB_USER`,
`NUBE_DB_PASS`.

## 8. Docker (opcional)

Podés correr un contenedor y proxear desde nginx. En el servidor:

```bash
sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker juan      # el usuario debe volver a entrar (push nuevo)
```

`docker-compose.yml` en el repo, y en `.nube/deploy`:

```bash
docker compose up -d --build
```

Nginx apunta al puerto publicado por el contenedor (`127.0.0.1:8080`). Para
dockerizados, considerá Docker Swarm/Kubernetes si necesitás más de un
servidor.

## 9. Rollback

El deploy es un `checkout -f` del ref que pusheaste. Para volver a un commit
anterior:

```bash
git log --oneline                 # elegí el commit bueno
git push --force prod <sha>:main  # mueve main y dispara el deploy
```

También podés etiquetar cada release y pushear el tag:

```bash
git tag -a v1.2.0 -m "v1.2.0"
git push prod v1.2.0              # el hook recibe refs/tags/v1.2.0
```

Atención: `git push --force` a `main` reescribe la historia. Hacelo solo si
sabés lo que hacés y nadie más pushea a ese remoto.

## 10. Zero downtime (avanzado)

El hook hace `checkout` **sobre el directorio vivo**: durante uno o dos
segundos puede haber archivos mezclados. Para la mayoría de los proyectos es
imperceptible; para producción crítica usá un esquema de releases:

```text
/var/www/blog.example.com/         symlink -> releases/2026-10-19-1200
└── releases/
    ├── 2026-10-19-1200/
    └── 2026-10-18-0900/
```

Cada deploy va a un directorio nuevo y al final se cambia el symlink
atómicamente (`ln -sfn`). Se implementa en `.nube/deploy`. Es más complejo y
queda fuera del alcance de Nube, pero el hook propio te da el punto de
entrada.

## 11. Logs

```bash
# Log del usuario
tail -f /home/juan/nube-deploy.log

# Errores de la app (Laravel)
tail -f /home/juan/www/blog.example.com/storage/logs/laravel.log

# nginx
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

## Checklist

- [ ] Remoto `prod` configurado.
- [ ] `.env.example` con placeholders y `.env` fuera de git.
- [ ] Primer push exitoso.
- [ ] URL responde por HTTPS.
- [ ] Log de deploy revisado.
- [ ] Rollback probado al menos una vez.

Siguiente: [06 · Seguridad](06-seguridad.md).
