# Contribuir

## Entorno

Los scripts corren en Linux (probados en Ubuntu 24.04) y esperan `bash`,
`git`, `openssl`, `gpg`, `mysql` y `acme.sh`. No están pensados para correr en
macOS.

## Estilo

- `bash` con `set -euo pipefail` al inicio de cada script ejecutable.
- Comillas dobles en variables: `"$NUBE_DOMAIN"`.
- Configuración y helpers compartidos en [`lib/nube.sh`](lib/nube.sh); los
  scripts lo cargan con `source "$NUBE_DIR/lib.sh"`.
- Mensajes de usuario en español; nombres de archivos y variables en inglés.
- No agregar secretos ni rutas absolutas del servidor original.

## Probar antes de mandar un PR

```bash
# Sintaxis
for f in *.sh lib.sh lib/*.sh install.sh; do bash -n "$f"; done

# Si tenes shellcheck
shellcheck install.sh *.sh lib.sh lib/*.sh
```

Prueba funcional en un VPS o VM descartable:

```bash
sudo ./install.sh
sudo nube-add-user test test@example.com "ssh-ed25519 AAAA... test"
sudo runuser -u test -- ns demo
sudo runuser -u test -- nr demo demo.nube.example.com | sudo mysql
# push de prueba
```

## Documentación

- Toda funcionalidad nueva va acompañada de documentación en `docs/`.
- Los enlaces internos son relativos y deben funcionar en GitHub.
- Si agregás un comando o variable, actualizá
  [`docs/referencia/comandos.md`](docs/referencia/comandos.md).

## Seguridad

Antes de proponer un cambio que toque permisos, SSH, nginx o secretos, leé
[`SECURITY.md`](SECURITY.md) y explicá el impacto en el PR.
