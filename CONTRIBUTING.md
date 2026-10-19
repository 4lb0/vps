# Contribuir

## Entorno

Los scripts corren en Linux (probados en Ubuntu 24.04) y esperan `bash`,
`git`, `openssl`, `gpg`, `mysql`, `nginx` y `acme.sh`. No están pensados para
correr en macOS.

## Estilo

- `bash` con `set -euo pipefail` al inicio de cada script ejecutable.
- Comillas dobles en variables: `"$NUBE_DOMAIN"`.
- Configuración y helpers compartidos en [`lib/nube.sh`](lib/nube.sh); los
  scripts lo cargan con `source "$NUBE_DIR/lib.sh"`.
- Mensajes de usuario en español; nombres de archivos y variables en inglés.
- No agregar secretos, rutas absolutas de servidores propios ni referencias a
  dominios personales. Los ejemplos usan `nube.example.com` y el usuario
  `nube`.
- La configuración que se instala en `/etc` vive en [`nginx/`](nginx/) y
  [`fail2ban/`](fail2ban/) y usa placeholders `#NUBE_*#` cuando depende de
  `/etc/nube/nube.conf`.

## Probar antes de mandar un PR

```bash
make lint          # sintaxis de todos los scripts
make shellcheck    # si tenés shellcheck
./tools/check-links.sh   # links relativos de la documentación
```

Prueba funcional en un VPS o VM descartable:

```bash
sudo ./bootstrap.sh --base-domain nube.example.com \
    --email test@example.com --ssh-key "$(cat ~/.ssh/id_ed25519.pub)"
sudo runuser -u nube -- nube-add-subdomain demo
sudo runuser -u nube -- nube-add-repository demo demo.nube.example.com | sudo mysql
# push de prueba de la app
git remote add server nube@nube.example.com:git/nube && git push server main
```

## Documentación

- Toda funcionalidad nueva va acompañada de documentación en `docs/`.
- Los enlaces internos son relativos y deben funcionar en GitHub
  (`./tools/check-links.sh`).
- Si agregás un comando o variable, actualizá
  [`docs/referencia/comandos.md`](docs/referencia/comandos.md).

## Seguridad

Antes de proponer un cambio que toque permisos, SSH, nginx o secretos, leé
[`SECURITY.md`](SECURITY.md) y explicá el impacto en el PR. Tené en cuenta que
el push al repositorio del servidor ejecuta `install.sh` como root: cualquier
cambio en ese flujo debe ser conservador.
