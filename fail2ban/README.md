# fail2ban para Nube

Configuracion lista para usar en un servidor Nube. Ver la explicacion completa
en [`docs/06-seguridad.md`](../docs/06-seguridad.md).

## Instalacion

```bash
sudo apt install -y fail2ban
sudo nube-apply-config          # copia los filtros y crea jail.local
sudo systemctl enable --now fail2ban
```

`nube-apply-config` (lo mismo que `install.sh`, y lo que corre cada
`git push server main`) copia `fail2ban/filter.d/*.conf` siempre, y crea
`/etc/fail2ban/jail.local` **solo si no existe**: si cambiaste el
`jail.local` del servidor, no se pisa.

Antes de reiniciar, edita `/etc/fail2ban/jail.local`:

- `ignoreip`: agrega tu IP de administracion (o la de tu VPN).
- Si cambias el puerto SSH, poné el mismo valor en `port` dentro de `[sshd]` y
  `[sshd-ddos]`; si no, fail2ban banea el puerto equivocado.
- Si usas Cloudflare, lee la seccion "Cloudflare y la IP real" en la doc de
  seguridad. Sin `real_ip`, fail2ban ve la IP de Cloudflare y puede banearla.

## Verificar

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client status nginx-nube-scan
sudo tail -f /var/log/fail2ban.log
```

## Desbanear

```bash
sudo fail2ban-client set sshd unbanip 203.0.113.50
```

## Probar sin esperar un ataque

Desde otra maquina (o con una IP que puedas desbanear):

```bash
ssh wronguser@tu-servidor      # 3 intentos
sudo fail2ban-client status sshd
```

No lo hagas desde la misma IP con la que administras si no tienes acceso
consola del proveedor.

## Archivos

| Archivo | Para que sirve |
| --- | --- |
| `jail.local` | Jails activos, tiempos y acciones |
| `filter.d/nginx-nube-scan.conf` | Detecta escaneos en el access log de nginx |

Los demas filtros (`sshd`, `nginx-http-auth`, `nginx-req-limit`,
`nginx-botsearch`, `recidive`) vienen incluidos con fail2ban.
