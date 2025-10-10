#!/bin/bash

# Final deployment without port conflicts
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

final_deploy() {
    print_info "Creating final docker-compose configuration..."
    
    # Create the final working configuration
    cat > docker-compose.final.yml << 'EOF'
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
    # Remove external port to avoid conflicts
    command: --default-authentication-plugin=mysql_native_password

volumes:
  nopcommerce_data:
  nopcommerce_db_data:
  nopcommerce_logs:
EOF

    # Transfer and deploy
    print_info "Transferring final configuration..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no docker-compose.final.yml "$SSH_USER@$OCI_IP:/home/ubuntu/"
    
    print_info "Starting nopCommerce services..."
    run_remote "
        cd /home/ubuntu
        
        # Clean up previous attempts
        docker-compose -f docker-compose.fixed.yml down || true
        docker-compose down || true
        docker system prune -f
        
        # Start with final configuration
        docker-compose -f docker-compose.final.yml up -d
        
        # Wait for services to initialize
        sleep 60
        
        echo 'Container Status:'
        docker ps
    "
    
    # Test deployment
    print_info "Testing final deployment..."
    sleep 10
    
    if curl -I "http://$OCI_IP" 2>/dev/null | grep -q "HTTP"; then
        print_status "🎉 SUCCESS! nopCommerce is running!"
        echo
        print_info "🌐 Application URL: http://$OCI_IP"
        print_info "📋 Complete the installation wizard"
        print_info "🗄️ Database connection details:"
        echo "   - Server: nopcommerce_mysql_server"
        echo "   - Database: nopCommerce"  
        echo "   - Username: root"
        echo "   - Password: nopCommerce_db_password"
        echo "   - Port: 3306 (internal)"
        echo
        print_status "✅ Deployment completed successfully!"
        
    else
        print_error "Deployment may still be starting. Checking logs..."
        run_remote "docker logs nopcommerce --tail=15"
        
        print_info "Wait a moment and try: http://$OCI_IP"
    fi
    
    # Cleanup
    rm -f docker-compose.final.yml
}

final_deploy