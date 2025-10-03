#!/bin/bash

# Script de despliegue automático para ChatNode en AWS EC2


echo "🚀 Iniciando despliegue de ChatNode en AWS EC2..."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para imprimir mensajes con color
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. Actualizar sistema
print_status "Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

# Instalar herramientas necesarias
print_status "Instalando herramientas necesarias..."
sudo apt install -y wget unzip curl

# 2. Instalar Node.js LTS
print_status "Instalando Node.js LTS..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verificar instalación
node_version=$(node --version)
npm_version=$(npm --version)
print_status "Node.js instalado: $node_version"
print_status "npm instalado: $npm_version"

# 3. Instalar PM2 globalmente
print_status "Instalando PM2..."
sudo npm install -g pm2 --silent --no-audit --no-fund

# 4. Instalar Nginx
print_status "Instalando Nginx..."
sudo apt install nginx -y

# 5. Configurar firewall
print_status "Configurando firewall..."
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw allow 4000
sudo ufw --force enable

# 6. Clonar el repositorio
print_status "Clonando repositorio de GitHub..."
if [ -d "ChatNodeSaul" ]; then
    print_warning "Directorio ChatNodeSaul ya existe. Eliminando y clonando de nuevo..."
    rm -rf ChatNodeSaul
fi

print_status "Configurando Git para clonación automática..."
# Configurar Git para no pedir credenciales
git config --global credential.helper store
git config --global user.name "DeployBot"
git config --global user.email "deploy@example.com"
git config --global init.defaultBranch main

# Configurar para clonación sin autenticación
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/echo

print_status "Clonando repositorio público desde GitHub..."
# Clonar repositorio público (sin autenticación)
git clone --depth 1 https://github.com/saulcortesmartinez/ChatNodeSaul.git
cd ChatNodeSaul

# Verificar que la clonación fue exitosa
if [ ! -f "index.js" ]; then
    print_warning "⚠️ Git clone falló, intentando descarga directa..."
    cd ..
    rm -rf ChatNodeSaul
    
    # Descargar como ZIP desde GitHub
    print_status "Descargando repositorio como ZIP..."
    wget -O ChatNodeSaul.zip https://github.com/saulcortesmartinez/ChatNodeSaul/archive/refs/heads/main.zip
    
    if [ -f "ChatNodeSaul.zip" ]; then
        print_status "Extrayendo archivo ZIP..."
        unzip -q ChatNodeSaul.zip
        mv ChatNodeSaul-main ChatNodeSaul
        rm ChatNodeSaul.zip
        cd ChatNodeSaul
        
        if [ -f "index.js" ]; then
            print_status "✅ Repositorio descargado exitosamente via ZIP"
        else
            print_error "❌ Error: No se pudo descargar el repositorio"
            print_status "Contenido del directorio actual:"
            ls -la
            exit 1
        fi
    else
        print_error "❌ Error: No se pudo descargar el repositorio"
        exit 1
    fi
else
    print_status "✅ Repositorio clonado exitosamente"
fi

# 7. Instalar dependencias
print_status "Instalando dependencias de Node.js..."
npm install --silent --no-audit --no-fund

# 8. Configurar PM2
print_status "Configurando PM2..."

# Limpiar procesos PM2 existentes
print_status "Limpiando procesos PM2 existentes..."
pm2 delete all 2>/dev/null || true
pm2 kill 2>/dev/null || true

# Verificar que estamos en el directorio correcto
print_status "Directorio actual:"
pwd
print_status "Contenido del directorio:"
ls -la

# Verificar que el archivo index.js existe
if [ -f "index.js" ]; then
    print_status "✅ Archivo index.js encontrado"
    pm2 start index.js --name "chat-app"
    pm2 startup systemd -u $USER --hp $HOME
    pm2 save
    print_status "✅ PM2 configurado correctamente"
else
    print_error "❌ Archivo index.js no encontrado en el directorio actual"
    print_status "Contenido del directorio:"
    ls -la
    exit 1
fi

# 9. Configurar Nginx como proxy reverso
print_status "Configurando Nginx..."
sudo tee /etc/nginx/sites-available/chatnode > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    # Configuración para archivos estáticos
    location / {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        
        # Timeouts para WebSockets
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Configuración específica para Socket.IO
    location /socket.io/ {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts específicos para WebSockets
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Habilitar el sitio
sudo ln -sf /etc/nginx/sites-available/chatnode /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Añadir configuración adicional para WebSockets
print_status "Añadiendo configuración adicional para WebSockets..."
sudo tee -a /etc/nginx/nginx.conf > /dev/null <<EOF

# Configuración adicional para WebSockets
http {
    # Aumentar buffer sizes para WebSockets
    proxy_buffering off;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    
    # Configuración para WebSockets
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' close;
    }
}
EOF

# Verificar configuración de Nginx
print_status "Verificando configuración de Nginx..."
sudo nginx -t

if [ $? -eq 0 ]; then
    print_status "Reiniciando Nginx..."
    sudo systemctl restart nginx
    sudo systemctl enable nginx
else
    print_error "Error en la configuración de Nginx"
    exit 1
fi

# 10. Verificar que todo esté funcionando
print_status "Verificando servicios..."
sleep 10

# Verificar que la aplicación esté sirviendo archivos
print_status "Verificando archivos estáticos..."
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/ || echo "Error accediendo a la aplicación"

# Verificar Socket.IO
print_status "Verificando Socket.IO..."
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/socket.io/ || echo "Error accediendo a Socket.IO"

# Verificar PM2
print_status "Verificando PM2..."
pm2_status=$(pm2 jlist 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
if [ "$pm2_status" = "online" ]; then
    print_status "✅ PM2: Aplicación ejecutándose correctamente"
else
    print_warning "⚠️ PM2: Verificar estado de la aplicación"
    print_status "Ejecutando: pm2 status"
    pm2 status
fi

# Verificar Nginx
print_status "Verificando Nginx..."
nginx_status=$(sudo systemctl is-active nginx 2>/dev/null || echo "unknown")
if [ "$nginx_status" = "active" ]; then
    print_status "✅ Nginx: Servicio activo"
else
    print_warning "⚠️ Nginx: Verificar estado del servicio"
    print_status "Ejecutando: sudo systemctl status nginx"
    sudo systemctl status nginx --no-pager
fi

# Obtener IP pública
public_ip=$(curl -s http://checkip.amazonaws.com/ 2>/dev/null || echo "No disponible")

echo ""
echo "🎉 ¡Despliegue completado!"
echo "=================================="
echo "📱 Aplicación disponible en:"
echo "   • URL directa: http://$public_ip:4000"
echo "   • URL con Nginx: http://$public_ip"
echo ""
echo "🔧 Comandos útiles:"
echo "   • Ver estado: pm2 status"
echo "   • Ver logs: pm2 logs chat-app"
echo "   • Reiniciar: pm2 restart chat-app"
echo "   • Monitoreo: pm2 monit"
echo "   • Ver logs de Nginx: sudo tail -f /var/log/nginx/error.log"
echo ""
echo "📋 IMPORTANTE:"
echo "   • Verificar que el puerto 4000 esté abierto en el Security Group de EC2"
echo "   • Si no funciona, revisar: sudo ufw status"
echo "   • Para debugging: pm2 logs chat-app --lines 50"
echo ""
echo "🔧 DEBUGGING DE SOCKET.IO:"
echo "   • Verificar conexión: curl http://$public_ip/socket.io/"
echo "   • Ver logs en tiempo real: pm2 logs chat-app --lines 100"
echo "   • Verificar Nginx: sudo tail -f /var/log/nginx/access.log"
echo "   • Reiniciar servicios: sudo systemctl restart nginx && pm2 restart chat-app"
echo ""
echo "🌐 URLs DE PRUEBA:"
echo "   • Aplicación: http://$public_ip"
echo "   • Socket.IO: http://$public_ip/socket.io/"
echo "   • Puerto directo: http://$public_ip:4000"
echo "=================================="
