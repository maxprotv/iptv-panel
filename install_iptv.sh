
#!/bin/bash

# install_iptv.sh
# Bu scripti kaydedin ve çalıştırın

# Sunucu bilgileri
PUBLIC_IP="51.20.77.118"
PRIVATE_IP="172.31.30.44"
PUBLIC_DNS="ec2-51-20-77-118.eu-north-1.compute.amazonaws.com"

echo "IPTV Panel Kurulumu Başlatılıyor..."

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
    php8.1 \
    php8.1-mysql \
    php8.1-curl \
    php8.1-xml \
    php8.1-mbstring \
    php8.1-zip \
    php8.1-gd \
    php8.1-fpm \
    php8.1-cli \
    unzip \
    git \
    ffmpeg \
    curl \
    net-tools \
    npm

# Composer kurulumu
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# Çalışma dizinine geç
cd /var/www/

# Eski dosyaları temizle
rm -rf html
mkdir html
cd html

# Laravel projesi oluştur
composer create-project laravel/laravel .

# .env dosyasını düzenle
cat > .env <<EOF
APP_NAME="IPTV Panel"
APP_ENV=production
APP_KEY=base64:$(php artisan key:generate --show)
APP_DEBUG=false
APP_URL=http://$PUBLIC_IP

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=iptv_db
DB_USERNAME=iptv_user
DB_PASSWORD=oguz123
EOF

# Veritabanı oluştur
mysql -e "
CREATE DATABASE iptv_db;
CREATE USER 'iptv_user'@'localhost' IDENTIFIED BY 'oguz123';
GRANT ALL PRIVILEGES ON iptv_db.* TO 'iptv_user'@'localhost';
FLUSH PRIVILEGES;"

# Model dosyalarını oluştur
cat > app/Models/Channel.php <<EOF
<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;

class Channel extends Model
{
    protected \$fillable = ['name', 'stream_url', 'logo', 'category', 'is_active'];
}
EOF

cat > app/Models/Package.php <<EOF
<?php
namespace App\Models;
use Illuminate\Database\Eloquent\Model;

class Package extends Model
{
    protected \$fillable = ['name', 'price', 'duration', 'channels'];
}
EOF

# Migration dosyalarını oluştur
php artisan make:migration create_channels_table
php artisan make:migration create_packages_table

# Migration içeriklerini düzenle
cat > database/migrations/*_create_channels_table.php <<EOF
<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        Schema::create('channels', function (Blueprint \$table) {
            \$table->id();
            \$table->string('name');
            \$table->string('stream_url');
            \$table->string('logo')->nullable();
            \$table->string('category');
            \$table->boolean('is_active')->default(true);
            \$table->timestamps();
        });
    }

    public function down()
    {
        Schema::dropIfExists('channels');
    }
};
EOF

cat > database/migrations/*_create_packages_table.php <<EOF
<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up()
    {
        Schema::create('packages', function (Blueprint \$table) {
            \$table->id();
            \$table->string('name');
            \$table->decimal('price', 10, 2);
            \$table->integer('duration');
            \$table->json('channels');
            \$table->timestamps();
        });
    }

    public function down()
    {
        Schema::dropIfExists('packages');
    }
};
EOF

# Admin kullanıcısı oluştur
php artisan tinker <<EOF
\$user = new App\Models\User();
\$user->name = 'oguz';
\$user->email = 'admin@admin.com';
\$user->password = Hash::make('oguz');
\$user->save();
EOF

# Migrationları çalıştır
php artisan migrate --force

# Laravel UI paketini ekle
composer require laravel/ui
php artisan ui bootstrap --auth

# NPM paketlerini yükle ve derle
npm install
npm run build

# View dosyalarını oluştur
mkdir -p resources/views/admin
mkdir -p resources/views/channels
mkdir -p resources/views/packages

# Admin dashboard view
cat > resources/views/admin/dashboard.blade.php <<EOF
@extends('layouts.app')
@section('content')
<div class="container">
    <div class="row">
        <div class="col-md-12">
            <h1>IPTV Yönetim Paneli</h1>
            <div class="card-deck mt-4">
                <div class="card">
                    <div class="card-body">
                        <h5 class="card-title">Kanallar</h5>
                        <p class="card-text">Toplam Kanal: {{ \$channelCount }}</p>
                        <a href="/channels" class="btn btn-primary">Yönet</a>
                    </div>
                </div>
                <div class="card">
                    <div class="card-body">
                        <h5 class="card-title">Paketler</h5>
                        <p class="card-text">Toplam Paket: {{ \$packageCount }}</p>
                        <a href="/packages" class="btn btn-primary">Yönet</a>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
@endsection
EOF

# Route dosyasını güncelle
cat > routes/web.php <<EOF
<?php
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return redirect('/login');
});

Auth::routes();

Route::middleware(['auth'])->group(function () {
    Route::get('/home', [App\Http\Controllers\HomeController::class, 'index'])->name('home');
    Route::resource('channels', App\Http\Controllers\ChannelController::class);
    Route::resource('packages', App\Http\Controllers\PackageController::class);
});
EOF

# Dosya izinlerini ayarla
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
chmod -R 777 /var/www/html/storage
chmod -R 777 /var/www/html/bootstrap/cache

# Apache konfigürasyonu
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

# Apache modüllerini etkinleştir
a2enmod rewrite
systemctl restart apache2

echo "=========================================="
echo "IPTV Panel kurulumu tamamlandı!"
echo "Panel URL: http://$PUBLIC_IP"
echo "Admin Girişi:"
echo "Email: admin@admin.com"
echo "Şifre: oguz"
echo "=========================================="
