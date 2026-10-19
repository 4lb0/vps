# Backups

Estrategia **3-2-1**: 3 copias, en 2 medios distintos, 1 fuera del servidor.
Un backup en el mismo VPS no protege contra perder el VPS.

## 1. Usuario de MySQL para backup

No uses `root`. Creá un usuario de solo lectura:

```sql
CREATE USER 'backup'@'127.0.0.1' IDENTIFIED BY 'contraseña-larga';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup'@'127.0.0.1';
FLUSH PRIVILEGES;
```

Y guardá las credenciales en `/root/.my.cnf` (modo `0600`):

```ini
[client]
user=backup
password=contraseña-larga
```

## 2. Script local

```bash
sudo install -m 0755 docs/ejemplos/backup/nube-backup.sh /usr/local/bin/nube-backup
sudo mkdir -p /var/backups/nube
sudo /usr/local/bin/nube-backup
```

Agregalo al cron de root:

```bash
sudo crontab -e
```

```cron
0 4 * * * /usr/local/bin/nube-backup >> /var/log/nube-backup.log 2>&1
```

## 3. Copia offsite con rclone

```bash
sudo apt install -y rclone
sudo rclone config          # configurar el remoto (S3, B2, Drive…)
```

Agregá al final del script o en otro cron:

```bash
rclone sync /var/backups/nube remoto:nube-backups \
  --create-empty-src-dirs \
  --log-file /var/log/nube-rclone.log
```

Alternativas: `restic` o `borg` (backups incrementales y cifrados). Si guardás
datos de terceros, cifrá el backup:

```bash
gpg --encrypt --recipient admin@example.com sites.tar.gz
```

## 4. Restaurar

Un backup sin restauración probada no sirve. Practicá en un servidor de
pruebas:

```bash
# Bases
gunzip < databases.sql.gz | mysql

# Sitios
tar xzf sites.tar.gz -C /

# Config
tar xzf config.tar.gz -C /
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl restart php8.3-fpm fail2ban
```

Después del restore:

1. Verificá permisos (`chown -R usuario:www-data /home/usuario/www`).
2. Revisá `secrets.gpg` del usuario de deploy.
3. Hacé un deploy de prueba para confirmar que el hook funciona.

## 5. Frecuencia sugerida

| Qué | Frecuencia | Retención |
| --- | --- | --- |
| Bases de datos | Diaria | 7–30 días |
| Archivos (`www`) | Diaria | 7 días |
| Config del servidor | Semanal o al cambiar | 4 semanas |
| Backup completo offsite | Semanal | 3 meses |
| Prueba de restauración | Trimestral | — |
