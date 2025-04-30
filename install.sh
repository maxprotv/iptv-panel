
#!/bin/bash

# Sunucu bilgileri
PUBLIC_IP="51.20.77.118"
PRIVATE_IP="172.31.30.44"
PUBLIC_DNS="ec2-51-20-77-118.eu-north-1.compute.amazonaws.com"
INSTANCE_ID="i-05a298e2493eba572"
REGION="eu-north-1"

echo "IPTV Panel AWS Kurulum Başlatılıyor..."
echo "Sunucu: $PUBLIC_DNS ($PUBLIC_IP)"

# Root kontrolü
if [ "$(id -u)" != "0" ]; then
   echo "Bu script root yetkisi gerektirir" 1>&2
   exit 1
fi

# Sistem güncellemesi
apt update && apt upgrade -y

# Apache ve PHP kaldırılıp yeniden kurulacak
apt remove --purge apache2 php* -y
apt autoremove -y
apt clean

# Gerekli paketlerin kurulumu
apt install -y apache2 \
    mysql-server \
    php8.1 \
    php8.1-mysql \
    php8.1-curl \
    php8.1-xml \
    php8.1-mbstring \
    php8.1-zip \
    php8.1-gd \
    php8.1-fpm \
    unzip \
    git \
    ffmpeg \
    curl \
    net-tools

# Composer kurulumu
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# Apache'yi durdur
systemctl stop apache2

# UFW'yi devre dışı bırak
ufw disable

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

# Web dizini temizleme ve hazırlama
rm -rf /var/www/html/*
mkdir -p /var/www/html/public

# Apache konfigürasyonu
cat > /etc/apache2/ports.conf <<EOF
Listen 80
Listen 443
EOF

# Virtual host ayarları - DNS ve IP'ye göre özelleştirilmiş
cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName $PUBLIC_DNS
    ServerAlias $PUBLIC_IP
    DocumentRoot /var/www/html/public
    
    <Directory /var/www/html/public>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
        Order allow,deny
        Allow from all
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Test sayfası oluştur
cat > /var/www/html/public/index.php <<EOF
<?php
echo "<h1>IPTV Panel Test Page</h1>";
echo "<p>Server: $PUBLIC_DNS</p>";
echo "<p>Public IP: $PUBLIC_IP</p>";
echo "<p>Private IP: $PRIVATE_IP</p>";
echo "<hr>";
phpinfo();
EOF

# .htaccess dosyası
cat > /var/www/html/public/.htaccess <<EOF
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /
    
    # Allow direct access to existing files
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    
    # Route everything else to index.php
    RewriteRule ^(.*)$ index.php [QSA,L]
</IfModule>

# Enable CORS
<IfModule mod_headers.c>
    Header set Access-Control-Allow-Origin "*"
</IfModule>
EOF

# Dosya izinlerini ayarla
chown -R www-data:www-data /var/www/html
find /var/www/html -type f -exec chmod 644 {} \;
find /var/www/html -type d -exec chmod 755 {} \;

# Apache modüllerini etkinleştir
a2enmod rewrite
a2enmod headers
a2enmod proxy_fcgi
a2enmod setenvif
a2enmod ssl

# PHP-FPM konfigürasyonu
sed -i 's/listen = \/run\/php\/php8.1-fpm.sock/listen = 127.0.0.1:9000/g' /etc/php/8.1/fpm/pool.d/www.conf

# PHP ayarları - AWS için optimize edilmiş
cat > /etc/php/8.1/apache2/php.ini <<EOF
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
max_input_time = 300
date.timezone = UTC
display_errors = Off
log_errors = On
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
error_log = /var/log/php_errors.log
EOF

# Apache ve PHP servislerini yeniden başlat
systemctl enable apache2
systemctl enable php8.1-fpm
systemctl restart php8.1-fpm
systemctl restart apache2

# AWS için hosts dosyasını güncelle
echo "$PRIVATE_IP $PUBLIC_DNS" >> /etc/hosts
echo "$PUBLIC_IP $PUBLIC_DNS" >> /etc/hosts

# Servislerin durumunu kontrol et
echo "Apache Status:"
systemctl status apache2 --no-pager
echo "PHP-FPM Status:"
systemctl status php8.1-fpm --no-pager
echo "MySQL Status:"
systemctl status mysql --no-pager

# Bağlantı testleri
echo "Bağlantı Testleri Yapılıyor..."
echo "1. HTTP Test (Public IP):"
curl -I http://$PUBLIC_IP
echo "2. HTTP Test (DNS):"
curl -I http://$PUBLIC_DNS
echo "3. Localhost Test:"
curl -I http://localhost

echo "=========================================="
echo "IPTV Panel AWS kurulumu tamamlandı!"
echo "Panel URL: http://$PUBLIC_IP"
echo "Panel DNS: http://$PUBLIC_DNS"
echo "Test URL: http://$PUBLIC_IP/test.php"
echo "Kullanıcı adı: oguz"
echo "Şifre: oguz"
echo "=========================================="
echo "Önemli Kontroller:"
echo "1. AWS Security Group kontrol edin (Ports 80, 443)"
echo "2. Instance public IP erişilebilirliğini kontrol edin"
echo "3. DNS çözünürlüğünü kontrol edin"
echo "=========================================="

# Log kontrolü
echo "Son Apache hataları:"
tail -n 5 /var/log/apache2/error.log
``