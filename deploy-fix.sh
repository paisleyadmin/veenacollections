#!/bin/bash

# Quick Fix and Redeploy
set -e

OCI_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && $1"
}

fix_and_deploy() {
    print_info "Creating fixed docker-compose.yml..."
    
    # Create corrected docker-compose file
    cat > docker-compose.fixed.yml << 'EOF'
version: '3.8'

services:
  nopcommerce_web:
    image: nopcommerce:latest
    container_name: nopcommerce
    ports:
      - "80:80"
    depends_on:
      - nopcommerce_database
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
    volumes:
      - nopcommerce_data:/app/App_Data
      - nopcommerce_logs:/app/logs

  nopcommerce_database:
    image: "mysql:8.0"
    container_name: nopcommerce_mysql_server
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: "nopCommerce_db_password"
      MYSQL_DATABASE: "nopCommerce"
      MYSQL_USER: "nopcommerce"
      MYSQL_PASSWORD: "nopCommerce_db_password"
    volumes:
      - nopcommerce_db_data:/var/lib/mysql
    ports:
      - "3306:3306"
    command: --default-authentication-plugin=mysql_native_password

volumes:
  nopcommerce_data:
  nopcommerce_db_data:
  nopcommerce_logs:
EOF

    # Transfer fixed compose file
    print_info "Transferring fixed configuration..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no docker-compose.fixed.yml "$SSH_USER@$OCI_IP:/home/ubuntu/"
    
    # Deploy with fixed configuration
    print_info "Starting services with fixed configuration..."
    run_remote "
        cd /home/ubuntu
        
        # Stop any running services
        docker-compose down || true
        
        # Use the fixed compose file
        docker-compose -f docker-compose.fixed.yml up -d
        
        # Wait for startup
        sleep 45
        
        # Show status
        echo 'Container Status:'
        docker ps
        
        echo
        echo 'Service Health:'
        docker-compose -f docker-compose.fixed.yml ps
    "
    
    # Test the deployment
    print_info "Testing deployment..."
    sleep 15
    
    if curl -f "http://$OCI_IP" > /dev/null 2>&1; then
        print_status "🎉 SUCCESS! nopCommerce is running on http://$OCI_IP"
        
        # Show deployment info
        echo
        print_info "🌐 Access: http://$OCI_IP"
        print_info "📋 Database Info:"
        echo "  - Server: nopcommerce_mysql_server"
        echo "  - Database: nopCommerce"
        echo "  - Username: root (or nopcommerce)"
        echo "  - Password: nopCommerce_db_password"
        
    else
        print_error "Still having issues. Checking logs..."
        run_remote "docker logs nopcommerce --tail=20"
    fi
    
    # Cleanup
    rm -f docker-compose.fixed.yml
}

fix_and_deploy