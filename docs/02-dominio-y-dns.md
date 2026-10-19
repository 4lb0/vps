# 02 · Dominio y DNS

Un dominio apunta a tu VPS mediante registros DNS. Esta guía cubre desde
comprar el dominio hasta tener `nube.example.com` y un wildcard
`*.nube.example.com` funcionando, más el certificado TLS.

## 1. Piezas: registrador, DNS y hosting

| Pieza | Qué hace | Ejemplos |
| --- | --- | --- |
| **Registrador** | Vende y renueva el dominio; define qué servidores DNS usan la zona | Namecheap, Porkbun, Cloudflare Registrar, GoDaddy, NIC.ar (.ar) |
| **Proveedor DNS** | Administra los registros (`A`, `CNAME`, `MX`…) | El propio registrador, Cloudflare, Route 53, Bunny DNS |
| **Hosting / VPS** | Corre la aplicación | Tu VPS con Nube |

Normalmente el registrador ofrece DNS gratuito y alcanza. Cloudflare agrega
proxy, CDN y protección DDoS, pero introduce detalles que hay que conocer (ver
más abajo).

## 2. Comprar el dominio

1. Entrá al registrador y buscá el nombre.
2. Comprá y **activá la renovación automática**.
3. Verificá tu email: sin eso el dominio puede suspenderse.
4. Si vas a usar un proveedor DNS distinto, cambiá los **nameservers (NS)** y
   esperá la propagación (puede tardar de minutos a 24 h).

Para `.ar` se registra en [NIC.ar](https://nic.ar). Para el resto, cualquier
registrador internacional sirve.

## 3. Apuntar el dominio al VPS

En el panel DNS del dominio (por ejemplo `example.com`) creá:

| Tipo | Nombre / Host | Valor | TTL |
| --- | --- | --- | --- |
| `A` | `@` (o vacío) | `203.0.113.10` | 300 |
| `A` | `www` | `203.0.113.10` | 300 |
| `A` | `nube` | `203.0.113.10` | 300 |
| `A` | `*` | `203.0.113.10` | 300 |

Qué significa cada uno:

- `@` es el dominio raíz (`example.com`).
- `www` es el alias clásico.
- `nube` crea `nube.example.com`, la base de las apps.
- `*` es el **wildcard**: cualquier subdominio no definido apunta también al
  VPS.

> **No uses `*` si tu dominio raíz también está en el VPS.** En ese caso
> definí `*.nube` (algunos paneles lo escriben como `*.nube` o `*` dentro de
> la zona `nube`). Lo importante es que exista un wildcard bajo el dominio
> base de Nube.

Si no definís `www`, es normal que `www.example.com` no responda. No es un
error de Nube.

### Ejemplo completo

```text
example.com              A      203.0.113.10
www.example.com          CNAME  example.com.
nube.example.com         A      203.0.113.10
*.nube.example.com       A      203.0.113.10
```

El wildcard hace que `mi-app.nube.example.com` funcione **sin** crear un
registro por app.

## 4. Propagación y verificación

Los DNS se propagan por TTL; con TTL 300 (5 minutos) los cambios se ven
rápido, pero los resolvers pueden cachear más tiempo.

```bash
# Desde tu máquina
dig +short example.com
dig +short nube.example.com
dig +short loquesea.nube.example.com     # debe devolver la misma IP

# Comparar con el DNS autoritativo
dig +short nube.example.com @1.1.1.1
dig +short nube.example.com @8.8.8.8

# Traza completa
dig nube.example.com +trace
```

Alternativas si no tenés `dig` (paquete `dnsutils`):

```bash
nslookup nube.example.com
host nube.example.com
```

Cuando la IP sea la correcta y `*.nube.example.com` resuelva, seguí con
[03 · Instalar Nube](03-instalar-nube.md).

## 5. Certificado wildcard para `*.nube.example.com`

El certificado wildcard cubre todas las apps bajo `nube.example.com` con un
solo certificado. Se emite con validación **DNS-01**, que no necesita HTTP y
es obligatoria para wildcards.

### Cloudflare

1. Creá un token de API con permiso **DNS:Edit** para la zona.
2. En el servidor:

```bash
export CF_Token="tu-token-de-cloudflare"
sudo -E /root/.acme.sh/acme.sh --issue \
  --dns dns_cf \
  -d '*.nube.example.com' \
  -d nube.example.com \
  --keylength ec-256 \
  --server letsencrypt
```

3. Instalá el certificado en una ruta estable para nginx:

```bash
sudo mkdir -p /etc/nginx/ssl
sudo /root/.acme.sh/acme.sh --install-cert \
  -d '*.nube.example.com' --ecc \
  --key-file       /etc/nginx/ssl/nube.key \
  --fullchain-file /etc/nginx/ssl/nube.crt \
  --reloadcmd      "systemctl reload nginx"
```

`--install-cert` registra la renovación automática y recarga nginx. El
wildcard queda en `/etc/nginx/ssl/nube.crt`.

### Otros proveedores DNS

acme.sh incluye adaptadores para Route 53, DigitalOcean, Hetzner, Vultr,
GoDaddy, etc.:

```bash
sudo /root/.acme.sh/acme.sh --issue --dns dns_aws -d '*.nube.example.com' -d nube.example.com
sudo /root/.acme.sh/acme.sh --issue --dns dns_dgon -d '*.nube.example.com' -d nube.example.com
```

Ver la lista completa en
[acme.sh/dnsapi](https://github.com/acmesh-official/acme.sh/wiki/dnsapi).

### Dominios propios (sin wildcard)

Para un dominio suelto (`app.example.com`), `nd` emite el certificado por
HTTP-01 usando acme.sh del usuario de deploy:

```bash
sudo runuser -u nube -- env HOME=/home/nube sh -c \
  'curl https://get.acme.sh | sh -s email=nube@example.com'

sudo runuser -u nube -- nd app.example.com
```

El certificado queda instalado en `/etc/nginx/ssl/app.example.com/`
(`fullchain.pem` y `key.pem`) y nginx lo toma por SNI. Para que el usuario
pueda escribir ahí, `/etc/nginx/ssl` debe existir con grupo `www-data` y modo
`2770` (lo crea `install.sh`; ver también [01](01-preparar-ubuntu.md#12-directorios-y-permisos)).

Si preferís no instalar acme.sh para el usuario, poné
`NUBE_ACME_MODE="none"` y gestioná los certificados desde root con
`--install-cert` hacia `/etc/nginx/ssl/<dominio>/`.

## 6. Cloudflare: proxy y IP real

Si activás el proxy de Cloudflare (nube naranja):

- El tráfico llega desde IPs de Cloudflare, no desde tus visitantes.
- El modo SSL debe ser **Full (strict)**; con `Flexible` hay loops y
  redirecciones raras.
- El wildcard proxied requiere plan pago. En el plan free, dejá los registros
  de las apps en gris (DNS-only) y proxeá solo el dominio principal.
- **fail2ban ve la IP de Cloudflare** en los logs de nginx. Hay que configurar
  `real_ip` para restaurar la IP original, o vas a banear a Cloudflare.

Para obtener la IP real, con el módulo `realip` de nginx:

```bash
mkdir -p /etc/nginx/snippets
curl -s https://www.cloudflare.com/ips-v4 -o /tmp/cf-ips-v4
curl -s https://www.cloudflare.com/ips-v6 -o /tmp/cf-ips-v6
```

```nginx
# /etc/nginx/snippets/cloudflare-real-ip.conf
set_real_ip_from 173.245.48.0/20;
# ... todas las redes de Cloudflare ...
real_ip_header CF-Connecting-IP;
real_ip_recursive on;
```

Incluilo dentro del bloque `server` (o en `http`). Después de eso,
`$remote_addr` vuelve a ser la IP del visitante y fail2ban funciona bien.

## 7. Correo: no lo hostees acá

Configurar un servidor de correo propio es un mundo aparte (SPF, DKIM, DMARC,
IPs con reputación, bloqueos). Recomendación: contratá un proveedor de correo
y configurá solo los registros DNS en tu dominio.

| Tipo | Nombre | Valor típico |
| --- | --- | --- |
| `MX` | `@` | `10 mx1.proveedor.com` |
| `TXT` | `@` | `v=spf1 include:proveedor.com ~all` |
| `TXT` | `selector._domainkey` | `v=DKIM1; k=rsa; p=...` |
| `TXT` | `_dmarc` | `v=DMARC1; p=none; rua=mailto:admin@example.com` |

Opcional: **rDNS / PTR** (lo configura el proveedor del VPS) para que la IP
tenga nombre inverso. No afecta al hosting web, sí al correo.

## 8. Errores comunes

| Síntoma | Causa probable |
| --- | --- |
| `dig` devuelve otra IP | Registro viejo con TTL alto, proxy activo o DNS cacheado |
| `*.nube.example.com` no resuelve | Falta el wildcard o el panel no acepta `*` en ese nivel |
| El navegador dice "no seguro" | El certificado todavía no se emitió o el `server_name` de nginx no coincide |
| `www` no funciona | No hay registro `CNAME`/`A` para `www` |
| Cambio que no se ve | TTL; probá con `dig @1.1.1.1` y esperá |
| Certificado inválido solo en algunos subdominios | El wildcard cubre un solo nivel (`*.nube.example.com` no cubre `a.b.nube.example.com`) |

El wildcard **no** cubre dos niveles: `*.nube.example.com` cubre
`app.nube.example.com`, pero no `a.b.nube.example.com`. Mantené los
subdominios en un solo nivel.

## Checklist

- [ ] Dominio comprado y con renovación automática.
- [ ] Registro `A` del dominio raíz apuntando al VPS.
- [ ] `nube.example.com` y `*.nube.example.com` apuntando al VPS.
- [ ] Verificado con `dig` (incluido un subdominio arbitrario).
- [ ] Certificado wildcard emitido e instalado en `/etc/nginx/ssl/`.
- [ ] Si usás Cloudflare: modo SSL Full (strict) y `real_ip` configurado.
- [ ] Correo delegado a un proveedor (SPF/DKIM/DMARC).

Siguiente: [03 · Instalar Nube](03-instalar-nube.md).
