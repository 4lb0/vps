# fail2ban para Nube

Configuracion lista para usar en un servidor Nube. Ver la explicacion completa
en [`docs/06-seguridad.md`](../docs/06-seguridad.md).

## Instalacion

```bash
sudo apt install fail2ban
sudo cp fail2ban/jail.local /etc/fail2ban/jail.local
sudo cp fail2ban/filter.d/*.conf /etc/fail2ban/filter.d/
sudo systemctl enable --now fail2ban
```

Antes de reiniciar, edita `/etc/fail2ban/jail.local`:

- `ignoreip`: agrega tu IP de administracion (o la de tu VPN).
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
