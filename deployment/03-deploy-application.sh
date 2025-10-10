#!/bin/bash

# ============================================================================
# nopCommerce Application Deployment Script
# ============================================================================
# This script deploys the nopCommerce application to the Oracle Cloud VM
# Run this script on your local macOS machine after server setup is complete
# ============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="/Users/majunu/PaisleyTech/VeenaCollections/nopCommerce"
SERVER_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}nopCommerce Application Deployment${NC}"
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

# Function to execute commands on remote server
ssh_exec() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/dotnet; $1"
}

# Function to copy files to remote server
scp_copy() {
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$1" "$SSH_USER@$SERVER_IP:$2"
}

# Check if deployment files exist
PUBLISH_DIR="$PROJECT_DIR/publish"
if [ ! -d "$PUBLISH_DIR" ]; then
    print_error "Published files not found. Please run ./01-prepare-local.sh first."
    exit 1
fi

# Find the latest deployment archive
DEPLOYMENT_ARCHIVE=$(find "$PROJECT_DIR" -name "nopcommerce-deployment-*.tar.gz" | sort -r | head -n 1)
if [ -z "$DEPLOYMENT_ARCHIVE" ]; then
    print_error "Deployment archive not found. Please run ./01-prepare-local.sh first."
    exit 1
fi

print_status "Found deployment archive: $(basename $DEPLOYMENT_ARCHIVE)"

# Test SSH connection
print_status "Testing SSH connection to server..."
if ! ssh_exec "echo 'SSH connection successful'"; then
    print_error "Cannot connect to server. Please check your SSH key and server availability."
    exit 1
fi

# Check if server setup is complete
print_status "Checking server prerequisites..."
if ! ssh_exec "command -v dotnet >/dev/null 2>&1"; then
    print_error ".NET runtime not found on server. Please run ./02-setup-server.sh first."
    exit 1
fi

if ! ssh_exec "systemctl is-active --quiet nginx"; then
    print_error "Nginx is not running on server. Please run ./02-setup-server.sh first."
    exit 1
fi

# Stop existing nopCommerce service if it exists
print_status "Stopping existing nopCommerce service..."
ssh_exec "sudo systemctl stop nopcommerce || true"

# Create backup of existing deployment if it exists
print_status "Creating backup of existing deployment..."
ssh_exec "
if [ -d /var/www/nopcommerce ] && [ -n \"\$(ls -A /var/www/nopcommerce 2>/dev/null)\" ]; then
    sudo mkdir -p /var/backups/nopcommerce
    sudo tar -czf /var/backups/nopcommerce/backup-\$(date +%Y%m%d-%H%M%S).tar.gz -C /var/www nopcommerce
    echo 'Existing deployment backed up'
else
    echo 'No existing deployment found'
fi
"

# Clean application directory
print_status "Preparing application directory..."
ssh_exec "
sudo rm -rf /var/www/nopcommerce/*
sudo mkdir -p /var/www/nopcommerce
"

# Copy deployment archive to server
print_status "Copying deployment files to server..."
scp_copy "$DEPLOYMENT_ARCHIVE" "/tmp/$(basename $DEPLOYMENT_ARCHIVE)"

# Extract deployment files
print_status "Extracting deployment files..."
ssh_exec "
cd /tmp
sudo tar -xzf $(basename $DEPLOYMENT_ARCHIVE) -C /var/www/nopcommerce/
sudo chown -R www-data:www-data /var/www/nopcommerce/ || sudo chown -R nginx:nginx /var/www/nopcommerce/
rm $(basename $DEPLOYMENT_ARCHIVE)
"

# Copy plugins configuration and update database connection
print_status "Copying plugins configuration from local machine..."
if [ -f "$PROJECT_DIR/src/Presentation/Nop.Web/App_Data/plugins.json" ]; then
    scp_copy "$PROJECT_DIR/src/Presentation/Nop.Web/App_Data/plugins.json" "/tmp/plugins.json"
    ssh_exec "
    sudo cp /tmp/plugins.json /var/www/nopcommerce/App_Data/plugins.json
    sudo chown www-data:www-data /var/www/nopcommerce/App_Data/plugins.json || sudo chown nginx:nginx /var/www/nopcommerce/App_Data/plugins.json
    rm /tmp/plugins.json
    echo 'Plugins configuration copied successfully'
    "
else
    print_warning "plugins.json not found locally, installation wizard may appear"
fi

print_status "Configuring database connection to bypass installation wizard..."
ssh_exec "
echo 'Updating appsettings.json with database connection...'
sudo sed -i 's/\"ConnectionString\": \"\"/\"ConnectionString\": \"Server=localhost;User ID=root;Password=Veen@;Database=veena;Allow User Variables=True;Use XA Transactions=False\"/g' /var/www/nopcommerce/App_Data/appsettings.json
sudo sed -i 's/\"DataProvider\": \"sqlserver\"/\"DataProvider\": \"mysql\"/g' /var/www/nopcommerce/App_Data/appsettings.json
echo 'Database connection configured for veena database'
"

# Install systemd service
print_status "Installing systemd service..."
ssh_exec "
sudo cp /var/www/nopcommerce/nopcommerce.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable nopcommerce
"

# Configure Nginx
print_status "Configuring Nginx..."
ssh_exec "
sudo cp /var/www/nopcommerce/nopcommerce.nginx.conf /etc/nginx/sites-available/nopcommerce
sudo ln -sf /etc/nginx/sites-available/nopcommerce /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
"

# Set correct permissions
print_status "Setting file permissions..."
ssh_exec "
sudo chown -R www-data:www-data /var/www/nopcommerce/ || sudo chown -R nginx:nginx /var/www/nopcommerce/
sudo chmod +x /var/www/nopcommerce/start-nopcommerce.sh
sudo chmod 644 /var/www/nopcommerce/App_Data/appsettings.json

# Create logs directory
sudo mkdir -p /var/www/nopcommerce/Logs
sudo chown www-data:www-data /var/www/nopcommerce/Logs || sudo chown nginx:nginx /var/www/nopcommerce/Logs
"

# Start nopCommerce service
print_status "Starting nopCommerce service..."
ssh_exec "sudo systemctl start nopcommerce"

# Wait for service to start
print_status "Waiting for application to start..."
sleep 10

# Check service status
print_status "Checking service status..."
if ssh_exec "systemctl is-active --quiet nopcommerce"; then
    print_status "nopCommerce service is running"
else
    print_error "nopCommerce service failed to start. Checking logs..."
    ssh_exec "sudo journalctl -u nopcommerce -n 20 --no-pager"
    exit 1
fi

# Test HTTP connectivity
print_status "Testing application connectivity..."
if ssh_exec "curl -s -o /dev/null -w '%{http_code}' http://localhost:5000 | grep -q '200\\|302\\|404'"; then
    print_status "Application is responding on port 5000"
else
    print_warning "Application may not be fully ready yet (this is normal for first startup)"
fi

# Display deployment information
print_status "Retrieving deployment information..."
ssh_exec "cat /var/www/nopcommerce/deployment-info.txt"

print_status "Deployment completed successfully!"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}Deployment Summary:${NC}"
echo -e "• Server: ${BLUE}$SERVER_IP${NC}"
echo -e "• Application URL: ${BLUE}http://$SERVER_IP${NC}"
echo -e "• Application Directory: ${BLUE}/var/www/nopcommerce${NC}"
echo -e "• Service Status: ${GREEN}Running${NC}"
echo -e "• Database: ${GREEN}MySQL (configured)${NC}"
echo -e "• Web Server: ${GREEN}Nginx (configured)${NC}"
echo ""
echo -e "${YELLOW}Post-Deployment Steps:${NC}"
echo -e "1. Visit ${BLUE}http://$SERVER_IP${NC} to complete nopCommerce installation"
echo -e "2. Follow the installation wizard to set up admin account"
echo -e "3. Configure SSL certificate for production use"
echo -e "4. Set up regular database backups"
echo ""
echo -e "${GREEN}Useful Commands (run on server):${NC}"
echo -e "• Check status: ${BLUE}sudo /usr/local/bin/nopcommerce-maintenance status${NC}"
echo -e "• View logs: ${BLUE}sudo /usr/local/bin/nopcommerce-maintenance logs${NC}"
echo -e "• Restart service: ${BLUE}sudo /usr/local/bin/nopcommerce-maintenance restart${NC}"
echo -e "• Backup database: ${BLUE}sudo /usr/local/bin/nopcommerce-maintenance backup-db${NC}"
echo -e "${BLUE}============================================================================${NC}"

# Open browser if possible (macOS)
if command -v open &> /dev/null; then
    print_status "Opening application in browser..."
    open "http://$SERVER_IP"
fi