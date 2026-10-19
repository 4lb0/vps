# 00 · Introducción: servidor, VPS, dominio y DNS

Antes de escribir comandos conviene tener claro qué piezas intervienen cuando
alguien abre `https://mi-app.example.com`. Esta guía es una introducción
práctica; no hace falta memorizarla para seguir el resto de la documentación.

## 1. Servidor, hosting y VPS

Un **servidor** es una computadora sin monitor ni teclado, conectada a
Internet, que atiende pedidos de otras computadoras. Cuando contratás un
servicio, en realidad alquilás una parte de una máquina:

| Modalidad | Qué te dan | Ventajas | Límites |
| --- | --- | --- | --- |
| **Hosting compartido** | Una cuenta dentro de un servidor con muchos clientes | Barato, panel incluido, soporte | Recursos compartidos, poca libertad, versiones fijas |
| **VPS** | Una máquina virtual con recursos reservados y acceso root | Control total, instalar lo que quieras, precio predecible | Vos administrás seguridad, backups y actualizaciones |
| **PaaS** (Heroku, Render, Vercel) | Solo la app; el proveedor administra el resto | Deploy simple, escalado | Costo por uso, menos control, dependencia del proveedor |
| **Cloud** (AWS, GCP, Azure) | Infraestructura granular | Escala y servicios gestionados | Complejidad y facturación difíciles de predecir |

Un VPS es el punto medio: te da la libertad de un servidor propio con un
costo mensual acotado. Nube justamente agrega sobre el VPS la comodidad de un
PaaS: `git push` y listo, pero sin perder el acceso root.

### ¿Cuánto necesito?

Para empezar y para varios proyectos chicos:

- **1–2 vCPU**
- **2 GB de RAM** (con 1 GB se puede, pero PHP + MySQL + Node se quedan justos)
- **40–80 GB de disco SSD**
- **Ubuntu 24.04 LTS** (soporte hasta 2029)

Un VPS de 2 GB suele costar entre USD 5 y 15 por mes según el proveedor y la
región. Proveedores habituales: Hetzner, DigitalOcean, Vultr, Linode, AWS
Lightsail, Scaleway. Todos ofrecen una imagen de Ubuntu y acceso por SSH.

## 2. Dominio y DNS

El **dominio** (`example.com`) es el nombre que las personas escriben. El
**DNS** (Domain Name System) es la guía telefónica que traduce ese nombre a
una dirección IP (`203.0.113.10`), que es donde realmente vive el servidor.

```text
navegador                 DNS                      VPS
   │                       │                        │
   │ "¿mi-app.example.com?"│                        │
   ├──────────────────────▶│                        │
   │                       │ "203.0.113.10"         │
   │◀──────────────────────┤                        │
   │                                                │
   ├──────────── HTTPS ────────────────────────────▶│ nginx
   │                                                │
```

Los registros DNS que vas a usar:

| Tipo | Para qué | Ejemplo |
| --- | --- | --- |
| `A` | Nombre → IPv4 | `example.com → 203.0.113.10` |
| `AAAA` | Nombre → IPv6 | `example.com → 2001:db8::1` |
| `CNAME` | Alias de otro nombre | `www → example.com` |
| `MX` | Correo | `example.com → mail.proveedor.com` |
| `TXT` | Verificaciones, SPF, DKIM | `v=spf1 ...` |
| `NS` | Qué servidores administran la zona | `ns1.proveedor.com` |

Para Nube necesitás dos registros especiales:

```text
nube.example.com       A   203.0.113.10
*.nube.example.com     A   203.0.113.10
```

El wildcard (`*`) hace que **cualquier** subdominio (`app.nube.example.com`,
`blog.nube.example.com`, etc.) apunte al mismo servidor. Sin él, cada app
nueva requeriría un registro DNS manual.

> El dominio se compra en un **registrador** (Namecheap, Porkbun, Cloudflare,
> NIC.ar para `.ar`, etc.). El registrador puede administrar el DNS él mismo o
> delegarlo a otro proveedor. En la guía de DNS está el detalle.

## 3. Cómo llega un pedido al servidor

Cuando alguien entra a `https://mi-app.example.com`:

1. El navegador resuelve el nombre por DNS y obtiene la IP del VPS.
2. Abre una conexión TCP al puerto 443.
3. Nginx recibe la conexión, presenta el certificado TLS y decide qué sitio
   servir según el header `Host`.
4. Si es un archivo estático, lo devuelve. Si es PHP, se lo pasa a
   **PHP-FPM**.
5. PHP-FPM ejecuta el código como el usuario `www-data` y, si hace falta,
   consulta **MySQL** en `127.0.0.1:3306`.
6. La respuesta vuelve por nginx al navegador.

En Nube, el sitio de `mi-app.example.com` vive en
`/var/www/mi-app.example.com/public`, que es un symlink al home del usuario de
deploy.

## 4. Tipos de proyecto y qué necesitan

| Proyecto | Qué corre en el servidor | En Nube |
| --- | --- | --- |
| HTML/CSS/JS estático | Solo nginx | Poné los archivos en `public/` |
| PHP (Laravel, WordPress, propio) | nginx + PHP-FPM | Soportado out of the box |
| Node.js | nginx + proceso Node (systemd/PM2) | Dependencias y build automáticos; receta para el proceso |
| Python | nginx + Gunicorn (systemd) | Dependencias automáticas; receta para el proceso |
| Go, Ruby | nginx + proceso propio | Receta manual |
| Docker | Docker + nginx como proxy | Receta manual |

No todos los proyectos necesitan lo mismo. Un sitio estático no requiere
PHP, MySQL ni Composer; una app Laravel sí. Instalar de más consume RAM y
aumenta la superficie de ataque. La guía de Ubuntu explica cómo instalar el
stack completo y qué se puede omitir.

## 5. Por qué un VPS y no un PaaS

Un PaaS es más simple al principio, pero:

- el costo crece rápido con varios proyectos;
- el entorno es menos flexible (versiones, extensiones, cron, workers);
- migrar después puede ser doloroso;
- no aprendés qué pasa debajo.

Un VPS con Nube te da:

- costo fijo y predecible;
- control de versiones de PHP, MySQL, Node;
- la posibilidad de correr varias apps y clientes en una sola máquina;
- el mismo flujo de `git push` que un PaaS.

La contrapartida es que **vos sos responsable** de la seguridad, los backups
y las actualizaciones. Por eso la documentación incluye una guía de seguridad
completa y una de operación.

## 6. Responsabilidades

| Tarea | ¿Quién? |
| --- | --- |
| Contratar y renovar el VPS | Vos |
| Comprar y renovar el dominio | Vos |
| Configurar DNS | Vos |
| Instalar y actualizar el sistema | Vos |
| Configurar TLS | `acme.sh` + nginx |
| Aislar el usuario y los permisos | Nube (con límites, ver seguridad) |
| Backups | Vos (hay script de ejemplo) |
| Código y dependencias de cada app | Cada proyecto |
| Soporte de la app | Vos |

## 7. Qué agrega Nube

Nube automatiza la parte repetitiva:

- crear un usuario sin shell y con claves SSH;
- mantener la configuración del servidor (nginx, fail2ban) en git y aplicarla
  con un push;
- crear repositorios bare y hooks de deploy;
- separar base de datos y credenciales por app;
- generar `.env` a partir de una plantilla;
- correr Composer, migraciones y caches de Laravel;
- instalar dependencias de Node y Python;
- emitir certificados y servir varios dominios con nginx.

Lo que **no** hace: no es un panel multi-tenant, no reemplaza un proveedor de
correo, no hace backups solo y no escala horizontalmente. Es una base chica y
legible para que la adaptes.

## Glosario

- **SSH**: protocolo para entrar a un servidor remoto. En Nube se usa con
  claves, sin contraseña.
- **TLS/HTTPS**: cifrado del tráfico entre el navegador y el servidor.
- **nginx**: servidor web y proxy inverso.
- **PHP-FPM**: proceso que ejecuta PHP por detrás de nginx.
- **git bare**: repositorio sin archivos de trabajo, pensado para recibir
  pushes.
- **hook**: script que git ejecuta en un evento (por ejemplo, después de un
  push).
- **wildcard**: registro DNS o certificado que cubre todos los subdominios.
- **reverse proxy**: servidor que recibe el pedido y lo deriva a otro proceso.
- **PaaS**: Platform as a Service, como Heroku o Render.

Siguiente: [01 · Preparar Ubuntu](01-preparar-ubuntu.md).
