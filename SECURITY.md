# Política de seguridad

## Alcance

Nube es un conjunto de scripts para publicar aplicaciones en un VPS propio
mediante `git push`. Corre con privilegios de root parcialmente (creación de
usuarios, nginx, MySQL) y expone SSH y HTTP/HTTPS a Internet.

## Modelo de seguridad

- Un VPS por administrador; los usuarios de deploy son de confianza relativa.
- Los usuarios de deploy tienen `git-shell` (sin shell interactivo) y no
  pertenecen a `sudo`.
- Cada app tiene su propia base de datos y su propio usuario de MySQL.
- Los secretos se guardan cifrados con GPG sin passphrase: protegen contra
  lectura casual, **no** contra acceso root.
- Por defecto todos los sitios comparten el pool de PHP-FPM (`www-data`). Para
  aislar clientes entre sí hay que configurar un pool por usuario.

## Superficie de ataque

- `sshd` (claves SSH, sin contraseñas).
- `nginx` (HTTP/HTTPS de todos los sitios).
- `PHP-FPM` y el código de cada aplicación.
- `MySQL` (solo localhost).
- `acme.sh` y su cron.

## Buenas prácticas obligatorias

1. Solo claves SSH; `PermitRootLogin no` y `PasswordAuthentication no`.
2. `AllowGroups sudo nube` y usuarios de deploy sin sudo.
3. UFW activo con solo 22, 80 y 443.
4. fail2ban activo (ver [`fail2ban/`](fail2ban/)).
5. MySQL en `127.0.0.1`, sin `local_infile`.
6. Actualizaciones automáticas de seguridad.
7. Backups probados.
8. Revisar dependencias de las apps.

El detalle está en [`docs/06-seguridad.md`](docs/06-seguridad.md).

## Reportar una vulnerabilidad

No abras un issue público con detalles explotables. Usá el reporte privado de
GitHub (Security → Report a vulnerability) del repositorio
`github.com/4lb0/vps`, o contactá al mantenedor por los canales del perfil.

Incluí:

- versión o commit;
- sistema operativo y versiones de nginx/PHP/MySQL;
- pasos para reproducir;
- impacto;
- cualquier mitigación que hayas encontrado.

Se intentará responder en pocos días. Si la vulnerabilidad está en una
dependencia (nginx, PHP, MySQL, acme.sh, fail2ban), reportala también aguas
arriba.
