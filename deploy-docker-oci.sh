#!/bin/bash

# nopCommerce Docker Deployment to OCI Always Free ARM Instance
# Optimized for Oracle Cloud Infrastructure ARM-based Ampere A1 VM

set -e

# Configuration from previous deployment
OCI_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"
PROJECT_DIR="/Users/majunu/PaisleyTech/VeenaCollections/nopCommerce"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Function to run commands on OCI instance
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "$1"
}

# Function to copy files to OCI instance
copy_to_remote() {
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$1" "$SSH_USER@$OCI_IP:$2"
}

# Function to copy directories to OCI instance
copy_dir_to_remote() {
    scp -r -i "$SSH_KEY" -o StrictHostKeyChecking=no "$1" "$SSH_USER@$OCI_IP:$2"
}

check_local_requirements() {
    print_info "Checking local requirements..."
    
    # Check if we're in the right directory
    if [ ! -f "src/NopCommerce.sln" ]; then
        print_error "Please run this script from the nopCommerce project root directory"
        print_error "Expected: $PROJECT_DIR"
        print_error "Current: $(pwd)"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    # Check SSH connectivity
    if ! run_remote "echo 'Connected'" > /dev/null 2>&1; then
        print_error "Cannot connect to OCI instance. Please check:"
        print_error "1. Instance IP: $OCI_IP"
        print_error "2. SSH key path: $SSH_KEY"
        print_error "3. Instance is running"
        exit 1
    fi
    
    print_status "Local requirements check passed"
}

prepare_local_build() {
    print_info "Building nopCommerce Docker image for ARM64..."
    
    # Build multi-architecture image for ARM64
    docker buildx create --use --name nopcommerce-builder 2>/dev/null || true
    docker buildx build --platform linux/arm64 -t nopcommerce:arm64 . --load
    
    # Save the image to a tar file for transfer
    print_info "Saving Docker image for transfer..."
    docker save nopcommerce:arm64 | gzip > nopcommerce-arm64.tar.gz
    
    print_status "Local build completed"
}

setup_oci_environment() {
    print_info "Setting up OCI VM environment..."
    
    # Create setup script
    cat > /tmp/oci-setup.sh << 'EOF'
#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start Docker service
    systemctl enable docker
    systemctl start docker
    
    # Add user to docker group
    usermod -aG docker ubuntu
    
    echo "Docker installed successfully"
else
    echo "Docker is already installed"
fi

# Install Docker Compose (standalone)
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "Docker Compose installed successfully"
fi

# Configure firewall
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw reload

# Create application directory
mkdir -p /home/ubuntu/nopcommerce
chown ubuntu:ubuntu /home/ubuntu/nopcommerce

# System optimization for nopCommerce
echo 'vm.swappiness=10' >> /etc/sysctl.conf
echo 'net.core.somaxconn=65535' >> /etc/sysctl.conf
sysctl -p

echo "OCI VM setup completed successfully"
EOF

    # Copy and execute setup script
    copy_to_remote "/tmp/oci-setup.sh" "/tmp/oci-setup.sh"
    run_remote "chmod +x /tmp/oci-setup.sh && sudo bash /tmp/oci-setup.sh"
    
    print_status "OCI environment setup completed"
}

deploy_application() {
    print_info "Deploying nopCommerce application to OCI..."
    
    # Create deployment package
    print_info "Creating deployment package..."
    tar czf nopcommerce-deployment.tar.gz \
        docker-compose.production.yml \
        nginx/ \
        .env.production \
        nopcommerce-arm64.tar.gz
    
    # Transfer deployment package
    print_info "Transferring deployment package..."
    copy_to_remote "nopcommerce-deployment.tar.gz" "/home/ubuntu/"
    
    # Deploy on remote server
    print_info "Extracting and deploying on OCI instance..."
    run_remote "
        cd /home/ubuntu
        tar xzf nopcommerce-deployment.tar.gz
        
        # Load Docker image
        echo 'Loading Docker image...'
        docker load < nopcommerce-arm64.tar.gz
        docker tag nopcommerce:arm64 nopcommerce:latest
        
        # Copy environment file
        cp .env.production .env
        
        # Create necessary directories
        mkdir -p ssl database/init
        
        # Start services
        echo 'Starting nopCommerce services...'
        docker-compose -f docker-compose.production.yml up -d
        
        # Wait for services to start
        echo 'Waiting for services to initialize...'
        sleep 30
        
        echo 'Checking service status...'
        docker-compose -f docker-compose.production.yml ps
    "
    
    print_status "Application deployment completed"
}

health_check() {
    print_info "Performing health check..."
    
    sleep 15  # Wait for services to fully start
    
    # Check if application is responding
    if curl -f "http://$OCI_IP" > /dev/null 2>&1; then
        print_status "✅ Application is healthy and responding!"
        print_info "nopCommerce is accessible at: http://$OCI_IP"
    else
        print_error "❌ Health check failed. Checking logs..."
        
        # Get container logs
        run_remote "
            echo '=== Container Status ==='
            docker ps -a
            echo
            echo '=== nopCommerce Logs ==='
            docker logs nopcommerce_web --tail=20
            echo
            echo '=== Database Logs ==='
            docker logs nopcommerce_database --tail=10
        "
        
        print_error "Please check the logs above for issues"
        return 1
    fi
}

show_deployment_info() {
    print_header "🎉 nopCommerce Deployment Completed!"
    echo
    print_info "🌐 Application URL: http://$OCI_IP"
    print_info "🔧 SSH Access: ssh -i $SSH_KEY $SSH_USER@$OCI_IP"
    echo
    print_header "📋 Next Steps:"
    echo "1. Open http://$OCI_IP in your browser"
    echo "2. Complete the nopCommerce installation wizard"
    echo "3. Database is pre-configured (MySQL)"
    echo
    print_header "🛠️ Management Commands:"
    echo "• View logs: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker-compose logs -f'"
    echo "• Restart: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker-compose restart'"
    echo "• Stop: ssh -i $SSH_KEY $SSH_USER@$OCI_IP 'docker-compose down'"
    echo "• Update: Re-run this script"
    echo
    print_info "💰 Total cost: \$0/month (Always Free tier)"
}

cleanup_local() {
    print_info "Cleaning up local files..."
    rm -f nopcommerce-arm64.tar.gz nopcommerce-deployment.tar.gz /tmp/oci-setup.sh
    print_status "Local cleanup completed"
}

# Main deployment function
main() {
    print_header "🚀 nopCommerce Docker Deployment to OCI Always Free"
    print_header "=================================================="
    
    echo
    echo "This will deploy nopCommerce with Docker to your OCI instance:"
    echo "• Instance: $OCI_IP"
    echo "• Architecture: ARM64 (Ampere A1)"
    echo "• Database: MySQL 8.0"
    echo "• Web Server: Nginx"
    echo "• Cache: Redis"
    echo "• SSL: Ready for Let's Encrypt"
    echo
    
    read -p "Continue with deployment? [Y/n]: " confirm
    if [[ ! $confirm =~ ^[Yy]?$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    echo
    check_local_requirements
    prepare_local_build
    setup_oci_environment
    deploy_application
    health_check
    show_deployment_info
    cleanup_local
    
    print_status "🎯 Deployment completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    "logs")
        run_remote "cd /home/ubuntu && docker-compose logs -f"
        ;;
    "status")
        run_remote "cd /home/ubuntu && docker-compose ps && docker stats --no-stream"
        ;;
    "restart")
        run_remote "cd /home/ubuntu && docker-compose restart"
        print_status "Services restarted"
        ;;
    "stop")
        run_remote "cd /home/ubuntu && docker-compose down"
        print_status "Services stopped"
        ;;
    "update")
        check_local_requirements
        prepare_local_build
        deploy_application
        health_check
        cleanup_local
        print_status "Update completed"
        ;;
    *)
        main
        ;;
esac