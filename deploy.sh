#!/bin/bash

# ============================================================================
# nopCommerce One-Click Deployment Script
# ============================================================================
# This script automates the entire deployment process
# Run this script from your project root directory
# ============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}nopCommerce One-Click Deployment to Oracle Cloud Infrastructure${NC}"
echo -e "${BLUE}============================================================================${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
PROJECT_DIR="/Users/majunu/PaisleyTech/VeenaCollections/nopCommerce"
SERVER_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

# Check if we're in the right directory
if [ ! -f "src/NopCommerce.sln" ]; then
    print_error "Please run this script from the nopCommerce project root directory"
    print_error "Expected: $PROJECT_DIR"
    print_error "Current: $(pwd)"
    exit 1
fi

# Create deployment directory if it doesn't exist
mkdir -p deployment

# Make all scripts executable
chmod +x deployment/*.sh 2>/dev/null || true

echo -e "${YELLOW}Choose deployment option:${NC}"
echo -e "1. Full deployment (recommended for first time)"
echo -e "2. Quick redeploy (if server is already set up)"
echo -e "3. Server setup only"
echo -e "4. Application deploy only"
echo -e "5. Check deployment status"
read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        print_status "Starting full deployment..."
        
        print_status "Step 1/3: Preparing local deployment..."
        ./deployment/01-prepare-local.sh
        
        print_status "Step 2/3: Setting up server..."
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; bash -s' < deployment/02-setup-server.sh
        
        print_status "Step 3/3: Deploying application..."
        ./deployment/03-deploy-application.sh
        
        print_status "Full deployment completed!"
        ;;
        
    2)
        print_status "Starting quick redeploy..."
        
        print_status "Step 1/2: Preparing local deployment..."
        ./deployment/01-prepare-local.sh
        
        print_status "Step 2/2: Deploying application..."
        ./deployment/03-deploy-application.sh
        
        print_status "Quick redeploy completed!"
        ;;
        
    3)
        print_status "Setting up server only..."
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; bash -s' < deployment/02-setup-server.sh
        print_status "Server setup completed!"
        ;;
        
    4)
        print_status "Deploying application only..."
        
        # Check if local build exists
        if [ ! -d "publish" ] && [ -z "$(find . -name 'nopcommerce-deployment-*.tar.gz' 2>/dev/null)" ]; then
            print_warning "No deployment files found. Preparing local deployment first..."
            ./deployment/01-prepare-local.sh
        fi
        
        ./deployment/03-deploy-application.sh
        print_status "Application deployment completed!"
        ;;
        
    5)
        print_status "Checking deployment status..."
        
        # Test SSH connection
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo 'SSH: Connected'" 2>/dev/null; then
            echo -e "• SSH Connection: ${GREEN}✓${NC}"
        else
            echo -e "• SSH Connection: ${RED}✗${NC}"
            exit 1
        fi
        
        # Check services
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            echo '=== Service Status ==='
            if systemctl is-active --quiet nopcommerce; then
                echo -e '• nopCommerce Service: \033[0;32m✓ Running\033[0m'
            else
                echo -e '• nopCommerce Service: \033[0;31m✗ Not Running\033[0m'
            fi
            
            if systemctl is-active --quiet nginx; then
                echo -e '• Nginx Service: \033[0;32m✓ Running\033[0m'
            else
                echo -e '• Nginx Service: \033[0;31m✗ Not Running\033[0m'
            fi
            
            if systemctl is-active --quiet mysql; then
                echo -e '• MySQL Service: \033[0;32m✓ Running\033[0m'
            else
                echo -e '• MySQL Service: \033[0;31m✗ Not Running\033[0m'
            fi
            
            echo -e '\n=== HTTP Response ==='
            if curl -s -o /dev/null -w '%{http_code}' http://localhost:5000 | grep -q '200\\|302\\|404'; then
                echo -e '• Application Response: \033[0;32m✓ Responding\033[0m'
            else
                echo -e '• Application Response: \033[0;31m✗ Not Responding\033[0m'
            fi
            
            echo -e '\n=== Recent Logs ==='
            journalctl -u nopcommerce -n 5 --no-pager
        "
        ;;
        
    *)
        print_error "Invalid choice. Please run the script again."
        exit 1
        ;;
esac

echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}Deployment Summary:${NC}"
echo -e "• Server IP: ${BLUE}$SERVER_IP${NC}"
echo -e "• Application URL: ${BLUE}http://$SERVER_IP${NC}"
echo -e "• SSH Access: ${BLUE}ssh -i $SSH_KEY $SSH_USER@$SERVER_IP${NC}"
echo ""
echo -e "${GREEN}Quick Commands:${NC}"
echo -e "• Check status: ${BLUE}ssh -i $SSH_KEY $SSH_USER@$SERVER_IP 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; sudo nopcommerce-maintenance status'${NC}"
echo -e "• View logs: ${BLUE}ssh -i $SSH_KEY $SSH_USER@$SERVER_IP 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; sudo nopcommerce-maintenance logs'${NC}"
echo -e "• Restart app: ${BLUE}ssh -i $SSH_KEY $SSH_USER@$SERVER_IP 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; sudo nopcommerce-maintenance restart'${NC}"
echo -e "${BLUE}============================================================================${NC}"

# Try to open browser (macOS)
if [[ "$choice" == "1" || "$choice" == "2" || "$choice" == "4" ]] && command -v open &> /dev/null; then
    read -p "Open application in browser? [y/N]: " open_browser
    if [[ "$open_browser" =~ ^[Yy]$ ]]; then
        open "http://$SERVER_IP"
    fi
fi