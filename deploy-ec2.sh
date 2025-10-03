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
git clone --depth 1 https://github.com/JManuelMMg/ChatNodeSaul.git
cd ChatNodeSaul

# Verificar que la clonación fue exitosa
if [ ! -f "index.js" ]; then
    print_warning "⚠️ Git clone falló, intentando descarga directa..."
    cd ..
    rm -rf ChatNodeSaul
    
    # Descargar como ZIP desde GitHub
    print_status "Descargando repositorio como ZIP..."
    wget -O ChatNodeSaul.zip https://github.com/JManuelMMg/ChatNodeSaul/archive/refs/heads/master.zip
    
    if [ -f "ChatNodeSaul.zip" ]; then
        print_status "Extrayendo archivo ZIP..."
        unzip -q ChatNodeSaul.zip
        mv ChatNodeSaul-master ChatNodeSaul
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

# Limpiar configuraciones existentes para evitar conflictos
print_status "Limpiando configuraciones existentes de Nginx..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-enabled/chatnode
sudo rm -f /etc/nginx/sites-available/chatnode

# Crear configuración limpia para ChatNode
print_status "Creando configuración de Nginx para ChatNode..."
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
print_status "Habilitando sitio de ChatNode..."
sudo ln -sf /etc/nginx/sites-available/chatnode /etc/nginx/sites-enabled/

# Verificar que no hay configuraciones duplicadas
print_status "Verificando configuraciones de Nginx..."
sudo nginx -t

if [ $? -eq 0 ]; then
    print_status "✅ Configuración de Nginx válida"
    print_status "Reiniciando Nginx..."
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    print_status "✅ Nginx configurado y reiniciado correctamente"
else
    print_error "❌ Error en la configuración de Nginx"
    print_status "Detalles del error:"
    sudo nginx -t 2>&1
    print_status "Intentando reparar configuración..."
    
    # Intentar reparar eliminando configuraciones problemáticas
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo rm -f /etc/nginx/sites-enabled/chatnode
    
    # Verificar configuración base de Nginx
    print_status "Verificando configuración base de Nginx..."
    sudo nginx -t
    
    if [ $? -eq 0 ]; then
        print_status "Recreando configuración de ChatNode..."
        sudo tee /etc/nginx/sites-available/chatnode > /dev/null <<EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        sudo ln -sf /etc/nginx/sites-available/chatnode /etc/nginx/sites-enabled/
        sudo nginx -t
        
        if [ $? -eq 0 ]; then
            print_status "✅ Configuración reparada exitosamente"
            sudo systemctl restart nginx
        else
            print_error "❌ No se pudo reparar la configuración de Nginx"
            print_status "Continuando sin Nginx (aplicación disponible en puerto 4000)"
        fi
    else
        print_error "❌ Error crítico en configuración base de Nginx"
        print_status "Continuando sin Nginx (aplicación disponible en puerto 4000)"
    fi
fi

# 10. Verificar que todo esté funcionando
print_status "Verificando servicios..."
sleep 10

# Función para verificar conectividad
check_service() {
    local service_name=$1
    local url=$2
    local expected_code=${3:-200}
    
    print_status "Verificando $service_name..."
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [ "$response_code" = "$expected_code" ] || [ "$response_code" = "000" ]; then
        print_status "✅ $service_name: Respondiendo correctamente (HTTP $response_code)"
        return 0
    else
        print_warning "⚠️ $service_name: Respuesta inesperada (HTTP $response_code)"
        return 1
    fi
}

# Verificar que la aplicación esté sirviendo archivos
check_service "Aplicación principal" "http://localhost:4000/"

# Verificar Socket.IO
check_service "Socket.IO" "http://localhost:4000/socket.io/"

# Verificar PM2
print_status "Verificando PM2..."
pm2_status=$(pm2 jlist 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
if [ "$pm2_status" = "online" ]; then
    print_status "✅ PM2: Aplicación ejecutándose correctamente"
else
    print_warning "⚠️ PM2: Verificar estado de la aplicación"
    print_status "Ejecutando: pm2 status"
    pm2 status
    
    # Intentar reiniciar si no está funcionando
    if [ "$pm2_status" != "online" ]; then
        print_status "Intentando reiniciar aplicación..."
        pm2 restart chat-app
        sleep 5
        pm2_status=$(pm2 jlist 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
        if [ "$pm2_status" = "online" ]; then
            print_status "✅ PM2: Aplicación reiniciada exitosamente"
        else
            print_error "❌ PM2: No se pudo reiniciar la aplicación"
        fi
    fi
fi

# Verificar Nginx
print_status "Verificando Nginx..."
nginx_status=$(sudo systemctl is-active nginx 2>/dev/null || echo "unknown")
if [ "$nginx_status" = "active" ]; then
    print_status "✅ Nginx: Servicio activo"
    
    # Verificar que Nginx esté sirviendo la aplicación
    nginx_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
    if [ "$nginx_response" = "200" ] || [ "$nginx_response" = "000" ]; then
        print_status "✅ Nginx: Proxy funcionando correctamente"
    else
        print_warning "⚠️ Nginx: Proxy no está funcionando (HTTP $nginx_response)"
        print_status "Verificando configuración de Nginx..."
        sudo nginx -t
    fi
else
    print_warning "⚠️ Nginx: Verificar estado del servicio"
    print_status "Ejecutando: sudo systemctl status nginx"
    sudo systemctl status nginx --no-pager
    
    # Intentar reiniciar Nginx si no está activo
    if [ "$nginx_status" != "active" ]; then
        print_status "Intentando reiniciar Nginx..."
        sudo systemctl restart nginx
        sleep 3
        nginx_status=$(sudo systemctl is-active nginx 2>/dev/null || echo "unknown")
        if [ "$nginx_status" = "active" ]; then
            print_status "✅ Nginx: Servicio reiniciado exitosamente"
        else
            print_error "❌ Nginx: No se pudo reiniciar el servicio"
        fi
    fi
fi

# Obtener IP pública
public_ip=$(curl -s http://checkip.amazonaws.com/ 2>/dev/null || echo "No disponible")

# Verificar estado final de todos los servicios
print_status "Resumen final del despliegue..."

# Estado de PM2
pm2_final_status=$(pm2 jlist 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
nginx_final_status=$(sudo systemctl is-active nginx 2>/dev/null || echo "unknown")

echo ""
echo "🎉 ¡Despliegue completado!"
echo "=================================="
echo "📊 ESTADO DE SERVICIOS:"
echo "   • PM2: $pm2_final_status"
echo "   • Nginx: $nginx_final_status"
echo "   • IP Pública: $public_ip"
echo ""
echo "📱 Aplicación disponible en:"
if [ "$nginx_final_status" = "active" ]; then
    echo "   • URL principal: http://$public_ip (con Nginx)"
    echo "   • URL directa: http://$public_ip:4000"
else
    echo "   • URL directa: http://$public_ip:4000 (sin Nginx)"
fi
echo ""
echo "🔧 COMANDOS DE GESTIÓN:"
echo "   • Ver estado: pm2 status"
echo "   • Ver logs: pm2 logs chat-app"
echo "   • Reiniciar app: pm2 restart chat-app"
echo "   • Monitoreo: pm2 monit"
echo "   • Ver logs Nginx: sudo tail -f /var/log/nginx/error.log"
echo "   • Ver logs acceso: sudo tail -f /var/log/nginx/access.log"
echo ""
echo "🔧 COMANDOS DE DEBUGGING:"
echo "   • Verificar app: curl http://localhost:4000/"
echo "   • Verificar Socket.IO: curl http://localhost:4000/socket.io/"
echo "   • Verificar Nginx: curl http://localhost/"
echo "   • Reiniciar todo: sudo systemctl restart nginx && pm2 restart chat-app"
echo "   • Ver configuración Nginx: sudo nginx -t"
echo ""
echo "📋 CONFIGURACIÓN DE SEGURIDAD:"
echo "   • Verificar Security Group EC2: puerto 80 y 4000 abiertos"
echo "   • Verificar firewall local: sudo ufw status"
echo "   • Verificar puertos: sudo netstat -tlnp | grep -E ':(80|4000)'"
echo ""
echo "🌐 URLs DE PRUEBA:"
if [ "$nginx_final_status" = "active" ]; then
    echo "   • Aplicación principal: http://$public_ip"
    echo "   • Socket.IO: http://$public_ip/socket.io/"
    echo "   • Puerto directo: http://$public_ip:4000"
else
    echo "   • Aplicación: http://$public_ip:4000"
    echo "   • Socket.IO: http://$public_ip:4000/socket.io/"
fi
echo ""
echo "🚨 SI ALGO NO FUNCIONA:"
echo "   1. Verificar logs: pm2 logs chat-app --lines 50"
echo "   2. Verificar Nginx: sudo systemctl status nginx"
echo "   3. Reiniciar servicios: sudo systemctl restart nginx && pm2 restart chat-app"
echo "   4. Verificar configuración: sudo nginx -t"
echo "   5. Verificar puertos: sudo netstat -tlnp | grep -E ':(80|4000)'"
echo "=================================="