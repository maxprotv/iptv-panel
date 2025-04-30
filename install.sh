
#!/bin/bash

echo "IPTV Panel Kurulum Başlatılıyor..."

# Root kontrolü
if [ "$(id -u)" != "0" ]; then
   echo "Bu script root yetkisi gerektirir" 1>&2
   exit 1
fi

# Sistem güncellemesi
apt update && apt upgrade -y

# Gerekli paketlerin kurulumu
apt install -y apache2 \
    mysql-server \
    php \
    php-mysql \
    php-curl \
    php-xml \
    php-mbstring \
    php-zip \
    php-gd \
    unzip \
    git \
    ffmpeg \
    composer

# Apache'yi durdur
systemctl stop apache2

# MySQL güvenli kurulum
mysql_secure_installation <<EOF

y
oguz123
oguz123
y
y
y
y
EOF

# Veritabanı oluşturma
mysql -u root -poguz123 <<EOF
CREATE DATABASE iptv_db;
CREATE USER 'iptv_user'@'localhost' IDENTIFIED BY 'oguz123';
GRANT ALL PRIVILEGES ON iptv_db.* TO 'iptv_user'@'localhost';
FLUSH PRIVILEGES;
EOF

# Web dizinine geç
cd /var/www/html

# Eski dosyaları temizle
rm -rf *

# IPTV panel dosyalarını indir
git clone https://github.com/yourusername/iptv-panel.git .

# Composer bağımlılıklarını yükle
composer install

# .env dosyasını oluştur
cat > .env <<EOF
APP_NAME=IPTV-Panel
APP_ENV=production
APP_KEY=$(php artisan key:generate --show)
APP_DEBUG=false
APP_URL=http://$(hostname -I | cut -d' ' -f1)

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=iptv_db
DB_USERNAME=iptv_user
DB_PASSWORD=oguz123

ADMIN_USERNAME=oguz
ADMIN_PASSWORD=oguz
EOF

# Veritabanı tablolarını oluştur
php artisan migrate --force

# Admin kullanıcısını oluştur
php artisan db:seed --force

# Apache yapılandırması
cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/public
    
    <Directory /var/www/html/public>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Public dizininde .htaccess oluştur
cat > /var/www/html/public/.htaccess <<EOF
<IfModule mod_rewrite.c>
    <IfModule mod_negotiation.c>
        Options -MultiViews -Indexes
    </IfModule>

    RewriteEngine On

    # Handle Authorization Header
    RewriteCond %{HTTP:Authorization} .
    RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

    # Redirect Trailing Slashes...
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteCond %{REQUEST_URI} (.+)/$
    RewriteRule ^ %1 [L,R=301]

    # Handle Front Controller...
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteRule ^ index.php [L]
</IfModule>
EOF

# Dosya izinlerini ayarla
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
chmod -R 777 /var/www/html/storage
chmod -R 777 /var/www/html/bootstrap/cache

# Apache modüllerini etkinleştir
a2enmod rewrite
a2enmod headers
a2ensite 000-default.conf

# Apache'yi yeniden başlat
systemctl restart apache2

# Güvenlik duvarı ayarları
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Yedekleme scripti oluştur
cat > /var/www/html/backup.sh <<EOF
#!/bin/bash
BACKUP_DIR="/var/backups/iptv-panel"
DATE=\$(date +%Y%m%d_%H%M%S)

mkdir -p \$BACKUP_DIR

# Veritabanı yedeği
mysqldump -u iptv_user -poguz123 iptv_db > \$BACKUP_DIR/db_\$DATE.sql

# Dosya yedeği
tar -czf \$BACKUP_DIR/files_\$DATE.tar.gz /var/www/html

# 7 günden eski yedekleri sil
find \$BACKUP_DIR -type f -mtime +7 -delete
EOF

chmod +x /var/www/html/backup.sh

# Otomatik yedekleme için cron görevi ekle
(crontab -l 2>/dev/null; echo "0 2 * * * /var/www/html/backup.sh") | crontab -

# Güncelleme scripti oluştur
cat > /var/www/html/update.sh <<EOF
#!/bin/bash
cd /var/www/html
git pull
composer install
php artisan migrate --force
php artisan cache:clear
php artisan config:clear
chown -R www-data:www-data /var/www/html
systemctl restart apache2
EOF

chmod +x /var/www/html/update.sh

# Kurulum tamamlandı bilgisi
IPADDR=$(hostname -I | cut -d' ' -f1)
echo "=========================================="
echo "IPTV Panel kurulumu tamamlandı!"
echo "Panel URL: http://$IPADDR"
echo "Kullanıcı adı: oguz"
echo "Şifre: oguz"
echo "=========================================="
echo ""
echo "Yedekleme scripti: /var/www/html/backup.sh"
echo "Güncelleme scripti: /var/www/html/update.sh"
echo "=========================================="
