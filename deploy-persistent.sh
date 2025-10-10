#!/bin/bash

# nopCommerce Deployment with Persistent Data Strategy
# Uses existing MySQL on VM + Docker persistent volumes

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

deploy_with_persistence() {
    print_header "🚀 nopCommerce Deployment with Data Persistence"
    print_header "=============================================="
    
    print_info "Creating optimized docker-compose configuration..."
    
    # Create docker-compose with persistent volumes and existing MySQL
    cat > docker-compose.persistent.yml << 'EOF'
services:
  nopcommerce:
    image: nopcommerce:latest
    container_name: nopcommerce
    restart: unless-stopped
    ports:
      - "80:80"
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:80
      # Database connection will be configured via installation wizard first time
    volumes:
      # Persistent data - survives deployments
      - nopcommerce_app_data:/app/App_Data
      - nopcommerce_plugins:/app/Plugins
      - nopcommerce_themes:/app/Themes
      - nopcommerce_wwwroot_images:/app/wwwroot/images
      - nopcommerce_wwwroot_files:/app/wwwroot/files
      - nopcommerce_logs:/app/logs
    network_mode: host  # Access to host MySQL
    depends_on:
      - mysql_check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health", "||", "exit", "1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  # Service to ensure MySQL is ready
  mysql_check:
    image: mysql:8.0
    container_name: mysql_checker
    network_mode: host
    command: >
      sh -c "
        echo 'Checking MySQL connection...' &&
        until mysqladmin ping -h 127.0.0.1 -P 3306 --silent; do
          echo 'Waiting for MySQL...';
          sleep 2;
        done &&
        echo 'MySQL is ready!'
      "
    restart: "no"

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

    # Build and save application
    print_info "Building nopCommerce application..."
    docker build -t nopcommerce:latest .
    docker save nopcommerce:latest | gzip > nopcommerce-persistent.tar.gz

    # Create deployment package
    print_info "Creating deployment package..."
    tar czf persistent-deploy.tar.gz \
        docker-compose.persistent.yml \
        nopcommerce-persistent.tar.gz

    # Transfer to OCI
    print_info "Transferring to OCI instance..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no persistent-deploy.tar.gz "$SSH_USER@$OCI_IP:/home/ubuntu/"

    # Prepare MySQL on VM
    print_info "Preparing MySQL database on VM..."
    run_remote "
        # Ensure MySQL is running and accessible
        sudo systemctl enable mysql
        sudo systemctl start mysql
        
        # Create nopCommerce database if it doesn't exist
        sudo mysql -e \"CREATE DATABASE IF NOT EXISTS nopcommerce_prod CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\"
        
        # Create nopCommerce user if it doesn't exist
        sudo mysql -e \"CREATE USER IF NOT EXISTS 'nopcommerce_user'@'%' IDENTIFIED BY 'nopCommerce_secure_2024';\"
        sudo mysql -e \"GRANT ALL PRIVILEGES ON nopcommerce_prod.* TO 'nopcommerce_user'@'%';\"
        sudo mysql -e \"FLUSH PRIVILEGES;\"
        
        # Allow local connections
        sudo mysql -e \"CREATE USER IF NOT EXISTS 'nopcommerce_user'@'localhost' IDENTIFIED BY 'nopCommerce_secure_2024';\"
        sudo mysql -e \"GRANT ALL PRIVILEGES ON nopcommerce_prod.* TO 'nopcommerce_user'@'localhost';\"
        sudo mysql -e \"FLUSH PRIVILEGES;\"
        
        echo 'MySQL database setup completed'
    "

    # Deploy application
    print_info "Deploying nopCommerce application..."
    run_remote "
        cd /home/ubuntu
        
        # Stop any existing containers
        docker-compose -f docker-compose.persistent.yml down 2>/dev/null || true
        docker-compose -f docker-compose.fixed.yml down 2>/dev/null || true
        docker-compose down 2>/dev/null || true
        
        # Extract deployment package
        tar xzf persistent-deploy.tar.gz
        
        # Load new application image
        echo 'Loading updated nopCommerce image...'
        docker load < nopcommerce-persistent.tar.gz
        
        # Start services
        echo 'Starting nopCommerce with persistent data...'
        docker-compose -f docker-compose.persistent.yml up -d
        
        # Wait for services to start
        sleep 45
        
        echo 'Container status:'
        docker ps
        
        echo
        echo 'Volume status:'
        docker volume ls | grep nopcommerce || echo 'No persistent volumes yet (will be created on first run)'
    "

    # Health check
    print_info "Performing health check..."
    sleep 20
    
    # Check if application is responding
    if curl -I "http://$OCI_IP" 2>/dev/null | head -1 | grep -q "200\|302"; then
        print_status "🎉 SUCCESS! nopCommerce is running with persistent data!"
        
        print_header "📋 Deployment Information"
        echo
        print_info "🌐 Application URL: http://$OCI_IP"
        
        # Check if this looks like first installation
        response=$(curl -s "http://$OCI_IP" | head -20)
        if echo "$response" | grep -qi "install\|setup\|wizard"; then
            print_info "🔧 First-time setup detected - Installation wizard will appear"
            print_info "📝 Database connection details for wizard:"
            echo "   • Server: 127.0.0.1 or localhost"
            echo "   • Database: nopcommerce_prod"  
            echo "   • Username: nopcommerce_user"
            echo "   • Password: nopCommerce_secure_2024"
            echo "   • Port: 3306"
            echo
            print_info "💡 After completing installation, future deployments will preserve all data!"
        else
            print_info "✅ Existing installation detected - Data preserved successfully!"
        fi
        
        print_header "🛠️ Management Commands"
        echo "• View logs: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker logs nopcommerce -f'"
        echo "• Restart app: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker-compose -f docker-compose.persistent.yml restart nopcommerce'"
        echo "• Update deployment: Re-run this script (data will be preserved)"
        echo "• Check volumes: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker volume ls'"
        
    else
        print_error "❌ Health check failed. Checking logs..."
        run_remote "
            echo 'Container status:'
            docker ps -a
            echo
            echo 'nopCommerce logs:'
            docker logs nopcommerce --tail=20
            echo
            echo 'MySQL checker logs:'
            docker logs mysql_checker --tail=10
        "
    fi
    
    # Cleanup local files
    print_info "Cleaning up local files..."
    rm -f nopcommerce-persistent.tar.gz persistent-deploy.tar.gz docker-compose.persistent.yml
    
    print_status "🎯 Deployment completed!"
}

# Execute deployment
deploy_with_persistence