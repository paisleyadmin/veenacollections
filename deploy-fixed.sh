#!/bin/bash

# nopCommerce Docker Deployment to OCI with PATH fixes
set -e

# Configuration
OCI_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "${BLUE}$1${NC}"; }

# Function to run commands with proper PATH
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && $1"
}

# Check requirements
check_requirements() {
    print_info "Checking local requirements..."
    
    if [ ! -f "src/NopCommerce.sln" ]; then
        print_error "Please run from nopCommerce project directory"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker is not running locally"
        exit 1
    fi
    
    print_status "Local requirements OK"
}

# Check OCI connection and clean up
check_and_clean_oci() {
    print_info "Checking OCI connection and cleaning previous attempts..."
    
    if ! run_remote "echo 'Connected successfully'" > /dev/null 2>&1; then
        print_error "Cannot connect to OCI instance"
        exit 1
    fi
    
    # Clean up any previous installations
    run_remote "
        # Stop any running services
        sudo systemctl stop nopcommerce || true
        sudo systemctl stop docker || true
        
        # Remove previous files
        sudo rm -rf /var/www/nopcommerce || true
        sudo rm -rf /home/ubuntu/nopcommerce || true
        sudo rm -f /etc/systemd/system/nopcommerce.service || true
        
        # Remove Docker if installed
        sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
        sudo apt-get autoremove -y || true
    "
    
    print_status "OCI cleanup completed"
}

# Install Docker on OCI
install_docker() {
    print_info "Installing Docker on OCI instance..."
    
    run_remote "
        # Update system
        sudo apt-get update
        
        # Install prerequisites
        sudo apt-get install -y ca-certificates curl gnupg lsb-release
        
        # Add Docker GPG key
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Add Docker repository
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # Start and enable Docker
        sudo systemctl enable docker
        sudo systemctl start docker
        
        # Add user to docker group
        sudo usermod -aG docker ubuntu
        
        # Install Docker Compose standalone
        sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        
        # Configure firewall
        sudo ufw --force enable
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw reload
    "
    
    print_status "Docker installation completed"
}

# Build and transfer application
build_and_transfer() {
    print_info "Building nopCommerce application..."
    
    # Build the local Docker image
    docker build -t nopcommerce:latest .
    
    # Save image to file
    print_info "Saving Docker image..."
    docker save nopcommerce:latest | gzip > nopcommerce-image.tar.gz
    
    # Create deployment package
    print_info "Creating deployment package..."
    tar czf deployment-package.tar.gz \
        docker-compose.yml \
        nginx.conf \
        nopcommerce-image.tar.gz
    
    # Transfer to OCI
    print_info "Transferring files to OCI..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no deployment-package.tar.gz "$SSH_USER@$OCI_IP:/home/ubuntu/"
    
    print_status "Build and transfer completed"
}

# Deploy application
deploy_application() {
    print_info "Deploying application on OCI..."
    
    run_remote "
        cd /home/ubuntu
        
        # Extract deployment package
        tar xzf deployment-package.tar.gz
        
        # Load Docker image
        echo 'Loading Docker image...'
        docker load < nopcommerce-image.tar.gz
        
        # Start services
        echo 'Starting nopCommerce services...'
        docker-compose up -d
        
        # Wait for startup
        sleep 30
        
        # Check status
        echo 'Checking container status...'
        docker ps
    "
    
    print_status "Application deployed"
}

# Health check
health_check() {
    print_info "Performing health check..."
    
    sleep 15
    
    if curl -f "http://$OCI_IP" > /dev/null 2>&1; then
        print_status "✅ Application is healthy!"
        print_info "🌐 Access: http://$OCI_IP"
    else
        print_error "❌ Health check failed"
        
        print_info "Checking logs..."
        run_remote "docker logs nopcommerce --tail=20"
        return 1
    fi
}

# Show final info
show_info() {
    print_header "🎉 nopCommerce Deployment Completed!"
    echo
    print_info "🌐 Application URL: http://$OCI_IP"
    print_info "🔧 SSH Access: ssh -i $SSH_KEY $SSH_USER@$OCI_IP"
    echo
    print_header "📋 Next Steps:"
    echo "1. Open http://$OCI_IP in your browser"
    echo "2. Complete nopCommerce installation"  
    echo "3. Database details:"
    echo "   - Server: nopcommerce_mysql_server"
    echo "   - Database: nopCommerce"
    echo "   - Username: root"
    echo "   - Password: nopCommerce_db_password"
    echo
    print_header "🛠️ Management Commands:"
    echo "• View logs: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker-compose logs -f'"
    echo "• Restart: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker-compose restart'"
    echo "• Stop: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker-compose down'"
}

# Cleanup local files
cleanup() {
    print_info "Cleaning up local files..."
    rm -f nopcommerce-image.tar.gz deployment-package.tar.gz
    print_status "Cleanup completed"
}

# Main deployment
main() {
    print_header "🚀 nopCommerce Docker Deployment to OCI"
    print_header "========================================"
    
    echo
    echo "Deploying to OCI instance: $OCI_IP"
    echo "This will install Docker and deploy nopCommerce"
    echo
    
    read -p "Continue? [Y/n]: " confirm
    if [[ ! $confirm =~ ^[Yy]?$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    check_requirements
    check_and_clean_oci
    install_docker
    build_and_transfer
    deploy_application
    health_check
    show_info
    cleanup
    
    print_status "🎯 Deployment completed successfully!"
}

# Handle commands
case "${1:-}" in
    "logs")
        run_remote "docker-compose logs -f"
        ;;
    "status")
        run_remote "docker ps && docker stats --no-stream"
        ;;
    "restart")
        run_remote "docker-compose restart"
        ;;
    "stop")
        run_remote "docker-compose down"
        ;;
    *)
        main
        ;;
esac