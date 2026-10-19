# systemd / PM2 para apps Node

Receta para correr una app Node con PM2 como el usuario de deploy, y nginx
como proxy inverso.

## 1. Instalar PM2 para el usuario

```bash
sudo runuser -u juan -- npm install -g pm2
sudo runuser -u juan -- env HOME=/home/juan pm2 startup systemd -u juan --hp /home/juan
# ejecutar el comando sudo que imprime
```

Alternativa: copiar `pm2-juan.service` a `/etc/systemd/system/` y
`systemctl enable --now pm2-juan`.

## 2. Archivos en el repo

```text
ecosystem.config.js        configuración de PM2 (abajo)
.nube/deploy               script ejecutable que PM2 usa en cada push
```

`ecosystem.config.js`:

```js
module.exports = {
  apps: [{
    name: "blog",
    script: "server.js",
    cwd: process.env.NUBE_PATH || "/home/juan/www/blog.example.com",
    instances: 1,
    env: { NODE_ENV: "production", PORT: 3000 }
  }]
};
```

`.nube/deploy`: ver [`../deploy/node-deploy.sh`](../deploy/node-deploy.sh).

## 3. nginx

En el `server` del dominio, reemplazar el include de PHP por:

```nginx
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade           $http_upgrade;
    proxy_set_header Connection        "upgrade";
}
```

El puerto debe ser único por app.

## 4. Verificar

```bash
sudo runuser -u juan -- env HOME=/home/juan pm2 status
sudo runuser -u juan -- env HOME=/home/juan pm2 logs blog
curl -I https://blog.example.com
```
