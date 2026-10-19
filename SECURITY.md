# Política de seguridad

## Alcance

Nube es un conjunto de scripts para publicar aplicaciones en un VPS propio
mediante `git push`. Corre con privilegios de root parcialmente (creación del
usuario, nginx, MySQL, fail2ban) y expone SSH y HTTP/HTTPS a Internet.

## Modelo de seguridad

- Un VPS por administrador, con **un solo usuario de deploy**.
- El usuario de deploy tiene `git-shell` (sin shell interactivo) y **no** tiene
  sudo general: solo puede ejecutar tres comandos acotados
  (`/etc/sudoers.d/nube`).
- Cada app tiene su propia base de datos, con un único usuario de MySQL.
- **Quien puede hacer push al repositorio del servidor puede instalar
  configuración como root** (es el objetivo del proyecto: `nginx/` y
  `fail2ban/` se aplican en cada push). Protegé esa clave: equivale a acceso
  root. Si no lo querés, quitá el permiso del sudoers y aplicá la
  configuración a mano.
- Los secretos se guardan cifrados con GPG sin passphrase: protegen contra
  lectura casual, **no** contra acceso root.
- Todos los sitios corren con el pool de PHP-FPM de `www-data`. Hay un solo
  usuario de deploy, así que el aislamiento entre clientes no aplica: si
  necesitás alojar clientes que no confían entre sí, usá un VPS por cliente.

## Superficie de ataque

- `sshd` (claves SSH, sin contraseñas; se recomienda un puerto no estándar
  con el 22 bloqueado).
- `nginx` (HTTP/HTTPS de todos los sitios).
- `PHP-FPM` y el código de cada aplicación.
- `MySQL` (solo localhost).
- `acme.sh` y su cron.
- El hook del repositorio del servidor (ejecuta `install.sh` como root).

## Buenas prácticas obligatorias

1. Solo claves SSH; `PermitRootLogin no` y `PasswordAuthentication no`.
2. `AllowGroups sudo nube` y sudo acotado para el usuario de deploy.
3. SSH en un puerto no estándar y el 22 bloqueado en el firewall
   (recomendado).
4. UFW activo con solo el puerto SSH elegido, 80 y 443.
5. fail2ban activo (ver [`fail2ban/`](fail2ban/)).
6. MySQL en `127.0.0.1`, sin `local_infile`.
7. Actualizaciones automáticas de seguridad.
8. Backups probados.
9. Revisar dependencias de las apps.

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
