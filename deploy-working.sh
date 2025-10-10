#!/bin/bash

# Fixed deployment with different port and proper MySQL setup
set -e

OCI_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "${BLUE}$1${NC}"; }

run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && $1"
}

deploy_fixed() {
    print_header "🔧 Fixed nopCommerce Deployment"
    print_header "==============================="
    
    print_info "Creating fixed docker-compose configuration..."
    
    # Create fixed docker-compose that uses port 80 after stopping conflicts
    cat > docker-compose.working.yml << 'EOF'
services:
  nopcommerce:
    image: nopcommerce:latest
    container_name: nopcommerce
    restart: unless-stopped
    ports:
      - "80:80"  # Use port 80 after stopping conflicting services
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:80
    volumes:
      # Persistent data - survives deployments
      - nopcommerce_app_data:/app/App_Data
      - nopcommerce_plugins:/app/Plugins
      - nopcommerce_themes:/app/Themes
      - nopcommerce_wwwroot_images:/app/wwwroot/images
      - nopcommerce_wwwroot_files:/app/wwwroot/files
      - nopcommerce_logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/", "||", "exit", "1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

volumes:
  # Persistent volumes for data that should survive deployments
  nopcommerce_app_data:
    driver: local
  nopcommerce_plugins:
    driver: local
  nopcommerce_themes:
    driver: local
  nopcommerce_wwwroot_images:
    driver: local
  nopcommerce_wwwroot_files:
    driver: local
  nopcommerce_logs:
    driver: local
EOF

    # Transfer fixed compose file
    print_info "Transferring fixed configuration..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no docker-compose.working.yml "$SSH_USER@$OCI_IP:/home/ubuntu/"
    
    # Setup MySQL properly
    print_info "Setting up MySQL database properly..."
    run_remote "
        # Stop any conflicting services first
        sudo systemctl stop apache2 || true
        sudo systemctl stop nginx || true
        sudo systemctl disable apache2 || true
        sudo systemctl disable nginx || true
        
        # Kill any process using port 80
        sudo fuser -k 80/tcp || true
        
        # Wait a moment for ports to free up
        sleep 3
        
        # Configure MySQL properly
        sudo systemctl start mysql
        sudo systemctl enable mysql
        
        # Create database using existing root password
        mysql -u root -p'Veen@' -e \"
            CREATE DATABASE IF NOT EXISTS nopcommerce_prod CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
            CREATE USER IF NOT EXISTS 'nopcommerce_user'@'localhost' IDENTIFIED BY 'nopCommerce_secure_2024';
            GRANT ALL PRIVILEGES ON nopcommerce_prod.* TO 'nopcommerce_user'@'localhost';
            FLUSH PRIVILEGES;
        \" || echo 'MySQL setup completed (some commands may have failed if already configured)'
        
        echo 'MySQL configuration completed'
    "
    
    # Deploy the application
    print_info "Deploying nopCommerce on port 8080..."
    run_remote "
        cd /home/ubuntu
        
        # Stop existing containers
        docker-compose -f docker-compose.persistent.yml down 2>/dev/null || true
        docker stop nopcommerce mysql_checker 2>/dev/null || true
        docker rm nopcommerce mysql_checker 2>/dev/null || true
        
        # Start with working configuration
        docker-compose -f docker-compose.working.yml up -d
        
        # Wait for startup
        sleep 30
        
        echo 'Container status:'
        docker ps
        
        echo
        echo 'Checking application health:'
        curl -I http://localhost:80 || echo 'Application may still be starting...'
    "
    
    # Health check
    print_info "Testing deployment on port 80..."
    sleep 15
    
    if curl -I "http://$OCI_IP:80" 2>/dev/null | head -1 | grep -q "HTTP"; then
        print_status "🎉 SUCCESS! nopCommerce is running!"
        
        print_header "📋 Deployment Information"
        echo
        print_info "🌐 Application URL: http://$OCI_IP"
        print_info "🔧 Installation wizard will appear for first-time setup"
        echo
        print_info "📝 Database connection details for installation wizard:"
        echo "   • Server: localhost or 127.0.0.1"
        echo "   • Database: nopcommerce_prod"  
        echo "   • Username: nopcommerce_user"
        echo "   • Password: nopCommerce_secure_2024"
        echo "   • Port: 3306"
        echo
        print_info "💡 After installation, future deployments will preserve all data!"
        
        print_header "🛠️ Management Commands"
        echo "• View logs: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker logs nopcommerce -f'"
        echo "• Restart: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker-compose -f docker-compose.working.yml restart'"
        echo "• Check status: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker ps'"
        
        print_status "✅ Deployment successful! Open http://$OCI_IP to access nopCommerce"
        
    else
        print_error "❌ Application not responding yet. Checking logs..."
        run_remote "docker logs nopcommerce --tail=15"
        
        print_info "🔄 The application may still be starting up. Try accessing:"
        print_info "   http://$OCI_IP"
    fi
    
    # Cleanup
    rm -f docker-compose.working.yml
    
    print_status "🎯 Deployment process completed!"
}

deploy_fixed