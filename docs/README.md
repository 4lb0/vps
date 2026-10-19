# Documentación de Nube

Este directorio explica cómo convertir un VPS Ubuntu en un servidor tipo
Heroku, donde cada proyecto se publica con `git push`.

## Por dónde empezar

| Si querés... | Leé |
| --- | --- |
| Entender qué es un VPS, un dominio y el DNS | [00 · Introducción](00-introduccion.md) |
| Contratar y preparar el servidor desde cero | [01 · Preparar Ubuntu](01-preparar-ubuntu.md) |
| Apuntar tu dominio al servidor | [02 · Dominio y DNS](02-dominio-y-dns.md) |
| Instalar Nube y configurar nginx | [03 · Instalar Nube](03-instalar-nube.md) |
| Crear usuarios, apps y bases de datos | [04 · Usuarios y apps](04-usuarios-y-aplicaciones.md) |
| Hacer el primer deploy y entender el hook | [05 · Deploy con git](05-deploy-con-git.md) |
| Cerrar el servidor y configurar fail2ban | [06 · Seguridad](06-seguridad.md) |
| Mantener, monitorear y respaldar | [07 · Operación y backups](07-operacion-y-backups.md) |
| Resolver un error | [08 · Solución de problemas](08-solucion-de-problemas.md) |

## Recorrido recomendado

```text
00 introducción
      │
      ▼
01 VPS Ubuntu ──▶ 02 dominio/DNS ──▶ 03 instalar Nube
                                          │
                                          ▼
                                   04 usuarios y apps
                                          │
                                          ▼
                                   05 primer deploy
                                          │
                          ┌───────────────┴───────────────┐
                          ▼                               ▼
                   06 seguridad                    07 operación
                          │                               │
                          └───────────────┬───────────────┘
                                          ▼
                                   08 troubleshooting
```

Tiempo estimado para tener la primera app publicada: **1 a 2 horas**,
incluyendo la propagación del DNS.

## Referencia

- [Arquitectura](referencia/arquitectura.md): qué pasa en un request y en un
  deploy, y cómo se relacionan usuarios, archivos y permisos.
- [Comandos y variables](referencia/comandos.md): todos los scripts, opciones
  y variables de `/etc/nube/nube.conf`.
- [Plantillas](referencia/plantillas.md): `.env`, hooks propios de la app y
  recetas para otros lenguajes.

## Ejemplos

- [`ejemplos/nginx/`](ejemplos/nginx/): configuración completa de nginx con
  TLS, rate limit y headers de seguridad.
- [`ejemplos/php-fpm/`](ejemplos/php-fpm/): pool de PHP-FPM por usuario para
  aislar sitios.
- [`ejemplos/systemd/`](ejemplos/systemd/): servicio para una app Node.
- [`ejemplos/backup/`](ejemplos/backup/): backup de bases y archivos a un
  destino remoto.

## Convenciones

- Los comandos que empiezan con `sudo` se ejecutan como root en el servidor.
- `<dominio>`, `<app>` y `<usuario>` son valores que tenés que reemplazar.
- Las rutas `~/...` son relativas al home del usuario de deploy, no al de
  root.
- La documentación está en español; los nombres de archivos y variables en
  inglés para mantener compatibilidad con los scripts.
