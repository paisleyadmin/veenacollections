#!/bin/bash

# Network-fixed deployment for nopCommerce
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

run_diagnostics() {
    print_header "🔍 Running Pre-Deployment Diagnostics"
    run_remote "
        echo '--- Docker PS ---'
        docker ps -a
        echo
        echo '--- Processes on Port 80 ---'
        sudo ss -tlnp | grep ':80' || echo 'No processes found on port 80'
        echo
        echo '--- Last 15 NopCommerce Logs ---'
        docker logs nopcommerce --tail 15 2>/dev/null || echo 'Could not retrieve nopcommerce logs.'
    "
    print_header "======================================="
}

deploy_network_fix() {
    run_diagnostics
    print_header "🔧 Network-Fixed nopCommerce Deployment"
    print_header "======================================="
    
    print_info "Creating network-fixed docker-compose configuration..."
    
    # Create docker-compose with host networking to access MySQL
    cat > docker-compose.network-fixed.yml << 'EOF'
services:
  nopcommerce:
    image: nopcommerce:latest
    container_name: nopcommerce
    restart: unless-stopped
    network_mode: "host"  # Use host networking to access MySQL
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
      test: ["CMD-SHELL", "curl -fsS -H 'Host: 129.146.167.43' http://localhost:80/ || exit 1"]
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
    print_info "Transferring network-fixed configuration..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no docker-compose.network-fixed.yml "$SSH_USER@$OCI_IP:/home/ubuntu/"
    
    # Configure MySQL to accept connections and ensure proper setup
    print_info "Configuring MySQL for container access..."
    run_remote "
        # Stop any conflicting services first
        sudo systemctl stop apache2 || true
        sudo systemctl stop nginx || true
        sudo systemctl disable apache2 || true
        sudo systemctl disable nginx || true
        
        # Kill any process using port 80
        sudo fuser -k 80/tcp || true
        sleep 3
        
        # Ensure MySQL is running and configured
        sudo systemctl start mysql
        sudo systemctl enable mysql
        
        # Verify and recreate database/user if needed
        mysql -u root -p'Veen@' -e \"
            CREATE DATABASE IF NOT EXISTS nopcommerce_prod CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
            CREATE USER IF NOT EXISTS 'nopcommerce_user'@'localhost' IDENTIFIED BY 'nopCommerce_secure_2024';
            CREATE USER IF NOT EXISTS 'nopcommerce_user'@'127.0.0.1' IDENTIFIED BY 'nopCommerce_secure_2024';
            GRANT ALL PRIVILEGES ON nopcommerce_prod.* TO 'nopcommerce_user'@'localhost';
            GRANT ALL PRIVILEGES ON nopcommerce_prod.* TO 'nopcommerce_user'@'127.0.0.1';
            FLUSH PRIVILEGES;
        \" 2>/dev/null || echo 'MySQL setup completed (some commands may have failed if already configured)'
        
        echo 'MySQL configuration completed'
        
        # Test database connection
        echo 'Testing database connection:'
        mysql -u nopcommerce_user -p'nopCommerce_secure_2024' -h localhost -e 'SELECT \"Connection successful\" as Status;' 2>/dev/null && echo 'Database connection: SUCCESS' || echo 'Database connection: FAILED'
    "
    
    # Transfer source code for fresh build
    print_info "Transferring source code..."
    
    # Create a clean source archive
    tar --exclude='.git' --exclude='bin' --exclude='obj' --exclude='node_modules' -czf /tmp/nopcommerce-src.tar.gz ./src ./Dockerfile
    
    # Transfer and extract
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/nopcommerce-src.tar.gz $SSH_USER@$OCI_IP:/tmp/
    run_remote "cd /home/ubuntu && rm -rf src Dockerfile && tar -xzf /tmp/nopcommerce-src.tar.gz && rm /tmp/nopcommerce-src.tar.gz"
    
    # Clean up local temp file
    rm -f /tmp/nopcommerce-src.tar.gz

    # Deploy the application with host networking
    print_info "Deploying nopCommerce with host networking..."
    run_remote "
        cd /home/ubuntu
        
        # Stop existing containers
        docker-compose -f docker-compose.working.yml down 2>/dev/null || true
        docker-compose -f docker-compose.persistent.yml down 2>/dev/null || true
        docker stop nopcommerce mysql_checker 2>/dev/null || true
        docker rm nopcommerce mysql_checker 2>/dev/null || true
        
        # Remove old image to force fresh build
        docker rmi nopcommerce:latest 2>/dev/null || true
        
        # Build fresh image with latest source code
        docker build --no-cache -t nopcommerce:latest .
        
        # Start with network-fixed configuration
        docker-compose -f docker-compose.network-fixed.yml up -d
        
        # Wait for startup
        sleep 30
        
        echo 'Container status:'
        docker ps
        
        echo
        echo 'Checking application health:'
        curl -I http://localhost:80 || echo 'Application may still be starting...'
    "
    
    # Health check
    print_info "Testing deployment..."
    sleep 15
    
    if curl -I "http://$OCI_IP" 2>/dev/null | head -1 | grep -q "HTTP"; then
        print_status "🎉 SUCCESS! nopCommerce is running with host networking!"
        
        print_header "📋 Updated Installation Information"
        echo
        print_info "🌐 Application URL: http://$OCI_IP"
        print_info "🔧 Installation wizard database details:"
        echo
        print_status "📝 USE THESE DATABASE CONNECTION DETAILS:"
        echo "   • Server: localhost"
        echo "   • Database: nopcommerce_prod"  
        echo "   • Username: nopcommerce_user"
        echo "   • Password: nopCommerce_secure_2024"
        echo "   • Port: 3306"
        echo
        print_info "🔗 With host networking, the container can now access MySQL!"
        print_info "💡 After installation, future deployments will preserve all data!"
        
        print_status "✅ Network-fixed deployment successful!"
        
    else
        print_error "❌ Application not responding yet. Checking logs..."
        run_remote "docker logs nopcommerce --tail=20"
        
        print_info "🔄 The application may still be starting up. Try accessing:"
        print_info "   http://$OCI_IP"
    fi
    
    # Cleanup
    rm -f docker-compose.network-fixed.yml
    
    print_status "🎯 Network-fixed deployment process completed!"
}

deploy_network_fix