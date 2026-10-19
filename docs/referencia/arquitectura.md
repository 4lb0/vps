# Arquitectura

Cómo se relacionan las piezas de Nube. Para el detalle de instalación, ver
[03 · Instalar Nube](../03-instalar-nube.md).

## Componentes

| Componente | Rol |
| --- | --- |
| `sshd` | Autenticación SSH por clave |
| `git-shell` | Shell restringido: solo comandos git |
| `git-receive-pack` | Recibe el push y actualiza el repo bare |
| `hooks/post-update` | Dispara el deploy |
| `nube-hook-post-update` | Hace el checkout, `.env`, Composer y Laravel |
| `nginx` | TLS, virtual hosts, archivos estáticos y proxy a PHP-FPM |
| `PHP-FPM` | Ejecuta PHP (por defecto como `www-data`) |
| `MySQL/MariaDB` | Base por app, usuario por usuario |
| `acme.sh` | Emite y renueva certificados |
| `fail2ban` | Banea IPs abusivas en SSH y nginx |
| `UFW` | Firewall del host |

## Flujo de un request

```text
Visitante
   │  HTTPS :443
   ▼
nginx ──► ¿Host = algo.nube.example.com?
   │         sí ──► root /var/www/algo.nube.example.com/public
   │         no ──► root /var/www/<host>/public
   │
   ├── archivo estático ──► respuesta directa
   │
   └── *.php ──► socket PHP-FPM ──► MySQL 127.0.0.1 ──► respuesta
```

Detalles:

- El server wildcard usa un certificado `*.nube.example.com`.
- Los dominios propios se resuelven por SNI: nginx busca el certificado en
  `/etc/nginx/ssl/<host>/`.
- El `root` es un symlink gestionado por `nd`/`ns`/`nr`.
- Nginx aplica headers de seguridad, rate limit y bloqueos de rutas.

## Flujo de un deploy

```text
1. git push prod main
2. sshd autentica la clave del usuario (git-shell)
3. git-receive-pack actualiza ~/git/<app>.git
4. post-update ejecuta nube-hook-post-update refs/heads/main <dominio> <gitdir>
5. el hook descifra ~/secrets.gpg (GPG)
6. git --work-tree=/var/www/<dominio> checkout -f <ref>
7. plantilla .env + placeholders #NUBE_*#
8. composer install (si hay composer.json)
9. Laravel: APP_KEY, permisos, caches, migraciones
10. .nube/deploy (si existe)
11. salida en la terminal del que hizo push + ~/nube-deploy.log
```

Puntos de falla y su efecto:

| Paso | Si falla |
| --- | --- |
| 2 | `Permission denied` en el push |
| 4 | El push se rechaza con el error del hook |
| 6 | Los archivos quedan en el estado anterior |
| 8 | Falla el deploy; el código nuevo ya está en disco |
| 9 | Igual que 8; revisar el log |

Nube **no** hace deploy atómico: el sitio puede ver un estado intermedio
durante el checkout. Para producción crítica, ver la sección de zero downtime
en [05](../05-deploy-con-git.md#10-zero-downtime-avanzado).

## Usuarios, archivos y permisos

```text
root
├── /usr/local/bin/{nr,nd,ns,nube-*}
├── /usr/local/lib/nube/
├── /etc/nube/nube.conf
├── /var/www -> symlinks (2775 root:www-data)
├── /var/www/acme (2775 www-data:www-data)
├── /etc/nginx/ssl (2770 root:www-data)
└── /home/<usuario> (0750 usuario:www-data)
    ├── .ssh (0700 usuario:usuario)
    ├── .acme.sh/ (si usa dominios propios)
    ├── secrets.gpg (0600)
    ├── git/<app>.git
    ├── www/<dominio>/public
    └── nube-deploy.log
```

| Sujeto | Puede |
| --- | --- |
| `root` | Todo |
| `www-data` | Leer los sitios, escribir `storage/` y `bootstrap/cache` |
| Usuario de deploy | Leer/escribir su home, hacer push a sus repos |
| Usuarios del grupo `nube` | Entrar por SSH, ejecutar solo comandos git |
| MySQL app A | Solo la base de app A |

### Límites del aislamiento

- Todos los sitios corren, por defecto, como `www-data`.
- Los usuarios comparten el grupo `www-data` y el grupo `nube`.
- `.env` y `secrets.gpg` son privados, pero un proceso PHP comprometido de
  otro sitio del mismo grupo podría leer archivos legibles por grupo.

Para separar de verdad: [pool de PHP-FPM por usuario](../06-seguridad.md#7-php-fpm-por-usuario).

## Recursos y escalado

Nube está pensado para **un servidor**. Cuando no alcanza:

1. Escalá verticalmente (más RAM/CPU/disco).
2. Separá MySQL a otro servidor.
3. Usá un balanceador/CDN delante de varios VPS (cada uno con su propio
   nginx y PHP-FPM), con un filesystem o deploy compartido.
4. Recién ahí pensá en contenedores/orquestación.

## Decisiones de diseño

- **Un repositorio bare por app** en lugar de un solo repo con carpetas: el
  push dispara un deploy independiente y los permisos son por usuario.
- **Symlinks en `/var/www`** en lugar de carpetas reales: los archivos viven
  en el home del usuario y nginx tiene una ruta estable.
- **GPG sin passphrase**: permite deploy no interactivo; protege contra
  lectura casual, no contra root.
- **Sin panel web**: menos superficie y menos piezas; todo es scripteable.
- **Laravel como caso principal**: el hook detecta `artisan` y hace los pasos
  habituales; el resto se personaliza con `.nube/deploy`.
