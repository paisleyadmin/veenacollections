#!/bin/bash

# Simplified OCI Docker Deployment for Minimal Environment
# Works with very basic shell environments

set -e

# Configuration
OCI_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Function to run commands on OCI with basic environment
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "$1"
}

# Simple preparation
prepare_simple() {
    print_info "Preparing simple deployment package..."
    
    # Create a minimal deployment package
    tar czf simple-nopcommerce.tar.gz \
        docker-compose.yml \
        nginx.conf \
        Dockerfile
    
    print_status "Simple package created"
}

# Check OCI environment
check_oci_basic() {
    print_info "Checking OCI environment basics..."
    
    # Test basic connectivity and commands
    run_remote "echo 'Basic connection OK' && /bin/ls -la"
    
    print_status "Basic OCI check completed"
}

# Install Docker with minimal commands
install_docker_minimal() {
    print_info "Installing Docker with minimal approach..."
    
    # Create a simple installation script that works with basic shell
    cat > /tmp/minimal-docker-install.sh << 'EOF'
#!/bin/bash

# Simple Docker installation for Ubuntu
/usr/bin/apt-get update
/usr/bin/apt-get install -y curl

# Add Docker repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | /usr/bin/apt-key add -
echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | /usr/bin/tee /etc/apt/sources.list.d/docker.list

# Install Docker
/usr/bin/apt-get update
/usr/bin/apt-get install -y docker-ce docker-ce-cli containerd.io

# Start Docker
/bin/systemctl enable docker
/bin/systemctl start docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
/bin/chmod +x /usr/local/bin/docker-compose

echo "Docker installation completed"
EOF

    # Copy and run installation
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/minimal-docker-install.sh "$SSH_USER@$OCI_IP:/tmp/"
    run_remote "/bin/bash /tmp/minimal-docker-install.sh"
    
    print_status "Docker installation completed"
}

# Deploy with basic approach
deploy_basic() {
    print_info "Deploying with basic approach..."
    
    # Copy files
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no simple-nopcommerce.tar.gz "$SSH_USER@$OCI_IP:/"
    
    # Extract and run
    run_remote "
        cd /
        /bin/tar xzf simple-nopcommerce.tar.gz
        /usr/local/bin/docker-compose up -d
    "
    
    print_status "Basic deployment completed"
}

# Test deployment
test_deployment() {
    print_info "Testing deployment..."
    
    # Wait and test
    sleep 30
    if curl -f "http://$OCI_IP" > /dev/null 2>&1; then
        print_status "✅ Application is responding!"
        print_info "Access: http://$OCI_IP"
    else
        print_error "❌ Application not responding"
        run_remote "/usr/local/bin/docker-compose logs"
    fi
}

# Main function
main() {
    echo "🚀 Simplified nopCommerce Docker Deployment"
    echo "============================================"
    
    check_oci_basic
    prepare_simple
    install_docker_minimal
    deploy_basic
    test_deployment
    
    print_status "Deployment completed!"
}

# Run main or handle commands
case "${1:-}" in
    "check")
        check_oci_basic
        ;;
    "install")
        install_docker_minimal
        ;;
    *)
        main
        ;;
esac