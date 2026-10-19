# Hooks propios de la app (`.nube/deploy`)

El hook de Nube ejecuta `.nube/deploy` (si existe y es ejecutable) al final de
cada deploy, **como el usuario de la app** y con la cwd en la raíz del
proyecto.

Variables disponibles:

| Variable | Valor |
| --- | --- |
| `NUBE_DOMAIN` | Dominio de la app |
| `NUBE_PATH` | `/var/www/<dominio>` |
| `NUBE_URL` | `https://<dominio>` |
| `NUBE_REFS` | Ref que se acaba de pushear |
| `NUBE_DB_USER` | Usuario de MySQL |
| `NUBE_DB_PASS` | Contraseña de MySQL |

## Ejemplos

- [`laravel-deploy.sh`](laravel-deploy.sh): `storage:link` y `queue:restart`.
- [`node-deploy.sh`](node-deploy.sh): `npm ci`, build y PM2.

## Uso

```bash
mkdir -p .nube
cp docs/ejemplos/deploy/laravel-deploy.sh .nube/deploy
chmod +x .nube/deploy
git add .nube/deploy
git commit -m "add deploy hook"
git push prod main
```

## Buenas prácticas

- Empezá con `set -euo pipefail`.
- No pongas secretos en el script: usá `.env` o las variables `NUBE_*`.
- Los pasos deben ser idempotentes: se ejecutan en cada push.
- No hagas `git clean` ni borres `storage/`: podés perder archivos subidos.
- Si el script falla, el deploy falla y queda registrado en el log.
