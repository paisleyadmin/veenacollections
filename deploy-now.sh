#!/bin/bash

# Direct nopCommerce Deployment (Docker already installed)
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

deploy_direct() {
    print_header "🚀 Direct nopCommerce Deployment"
    print_header "=================================="
    
    # Build local image
    print_info "Building nopCommerce image locally..."
    docker build -t nopcommerce:latest .
    
    # Save and compress image
    print_info "Saving Docker image..."
    docker save nopcommerce:latest | gzip > nopcommerce-image.tar.gz
    
    # Create deployment package
    print_info "Creating deployment package..."
    tar czf quick-deploy.tar.gz \
        docker-compose.yml \
        nginx.conf \
        nopcommerce-image.tar.gz
    
    # Transfer files
    print_info "Transferring to OCI..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no quick-deploy.tar.gz "$SSH_USER@$OCI_IP:/home/ubuntu/"
    
    # Deploy on OCI
    print_info "Deploying on OCI instance..."
    run_remote "
        cd /home/ubuntu
        
        # Clean up any existing containers
        docker-compose down || true
        docker system prune -f || true
        
        # Extract new deployment
        tar xzf quick-deploy.tar.gz
        
        # Load Docker image
        echo 'Loading nopCommerce image...'
        docker load < nopcommerce-image.tar.gz
        
        # Start services
        echo 'Starting services...'
        docker-compose up -d
        
        # Wait for startup
        sleep 30
        
        # Show status
        echo 'Container Status:'
        docker ps
        
        echo 'Service Health:'
        docker-compose ps
    "
    
    # Health check
    print_info "Testing deployment..."
    sleep 15
    
    if curl -f "http://$OCI_IP" > /dev/null 2>&1; then
        print_status "✅ SUCCESS! nopCommerce is running!"
        print_header "🌐 Access your application: http://$OCI_IP"
        print_info "Complete the installation wizard in your browser"
    else
        print_error "❌ Deployment failed. Checking logs..."
        run_remote "docker logs nopcommerce --tail=10"
        return 1
    fi
    
    # Cleanup
    rm -f nopcommerce-image.tar.gz quick-deploy.tar.gz
    
    print_status "🎯 Deployment completed!"
}

deploy_direct