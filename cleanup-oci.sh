#!/bin/bash

# OCI VM Cleanup Script - Remove all previous deployment attempts
# This script will clean up failed nopCommerce deployments on OCI

set -e

# Configuration - UPDATE THESE VALUES
OCI_IP="129.146.167.43"             # Your OCI instance IP
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"  # Path to your SSH private key
SSH_USER="ubuntu"                   # SSH username for your instance

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Function to run commands on OCI instance
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "$1"
}

# Check connection to OCI instance
check_connection() {
    print_info "Testing connection to OCI instance..."
    
    if run_remote "echo 'Connection successful'" > /dev/null 2>&1; then
        print_status "Successfully connected to OCI instance: $OCI_IP"
    else
        print_error "Cannot connect to OCI instance. Please check:"
        print_error "1. Instance IP: $OCI_IP"
        print_error "2. SSH key path: $SSH_KEY"
        print_error "3. Security group allows SSH (port 22)"
        print_error "4. Instance is running"
        exit 1
    fi
}

# Stop all running services
stop_services() {
    print_info "Stopping all running services..."
    
    run_remote "
        # Stop systemd services
        sudo systemctl stop nopcommerce || true
        sudo systemctl disable nopcommerce || true
        sudo systemctl stop nginx || true
        sudo systemctl stop apache2 || true
        sudo systemctl stop httpd || true
        
        # Stop Docker containers if any
        sudo docker stop \$(sudo docker ps -aq) || true
        sudo docker rm \$(sudo docker ps -aq) || true
        
        # Kill any .NET processes
        sudo pkill -f dotnet || true
        sudo pkill -f nop || true
        sudo pkill -f Nop.Web || true
        
        # Kill any process using ports 80, 443, 5000, 5001
        sudo fuser -k 80/tcp || true
        sudo fuser -k 443/tcp || true
        sudo fuser -k 5000/tcp || true
        sudo fuser -k 5001/tcp || true
    "
    
    print_status "Services stopped"
}

# Remove application files
remove_files() {
    print_info "Removing application files and directories..."
    
    run_remote "
        # Remove common deployment directories
        sudo rm -rf /var/www/nopcommerce || true
        sudo rm -rf /opt/nopcommerce || true
        sudo rm -rf /home/$SSH_USER/nopcommerce || true
        sudo rm -rf /root/nopcommerce || true
        
        # Remove systemd service files
        sudo rm -f /etc/systemd/system/nopcommerce.service || true
        sudo rm -f /lib/systemd/system/nopcommerce.service || true
        
        # Remove nginx/apache config files
        sudo rm -f /etc/nginx/sites-available/nopcommerce || true
        sudo rm -f /etc/nginx/sites-enabled/nopcommerce || true
        sudo rm -f /etc/apache2/sites-available/nopcommerce.conf || true
        sudo rm -f /etc/httpd/conf.d/nopcommerce.conf || true
        
        # Remove logs
        sudo rm -rf /var/log/nopcommerce || true
        sudo rm -rf /var/log/aspnetcore || true
        
        # Remove any temp files
        sudo rm -rf /tmp/nop* || true
        sudo rm -rf /tmp/dotnet* || true
    "
    
    print_status "Application files removed"
}

# Clean up Docker
cleanup_docker() {
    print_info "Cleaning up Docker containers and images..."
    
    run_remote "
        if command -v docker &> /dev/null; then
            # Remove all containers
            sudo docker container prune -f || true
            
            # Remove all images
            sudo docker image prune -a -f || true
            
            # Remove all volumes
            sudo docker volume prune -f || true
            
            # Remove all networks
            sudo docker network prune -f || true
            
            # Remove all build cache
            sudo docker builder prune -a -f || true
        fi
    "
    
    print_status "Docker cleanup completed"
}

# Reset firewall rules
reset_firewall() {
    print_info "Resetting firewall rules..."
    
    run_remote "
        # For Oracle Linux/CentOS/RHEL
        if command -v firewall-cmd &> /dev/null; then
            sudo firewall-cmd --reload || true
            sudo firewall-cmd --remove-service=http --permanent || true
            sudo firewall-cmd --remove-service=https --permanent || true
            sudo firewall-cmd --remove-port=5000/tcp --permanent || true
            sudo firewall-cmd --remove-port=5001/tcp --permanent || true
            sudo firewall-cmd --reload || true
        fi
        
        # For Ubuntu/Debian
        if command -v ufw &> /dev/null; then
            sudo ufw --force reset || true
            sudo ufw --force enable || true
        fi
        
        # Clear iptables rules (backup first)
        sudo iptables-save > /tmp/iptables-backup || true
        sudo iptables -F || true
        sudo iptables -X || true
        sudo iptables -t nat -F || true
        sudo iptables -t nat -X || true
    "
    
    print_status "Firewall rules reset"
}

# Remove installed packages
remove_packages() {
    print_info "Removing previously installed packages..."
    
    run_remote "
        # Remove .NET packages
        sudo dnf remove -y dotnet* aspnetcore* || true
        sudo yum remove -y dotnet* aspnetcore* || true
        sudo apt-get remove -y dotnet* aspnetcore* || true
        
        # Remove nginx/apache if installed for nopcommerce
        # (keeping this commented to avoid breaking other services)
        # sudo dnf remove -y nginx apache2 httpd || true
        # sudo yum remove -y nginx apache2 httpd || true
        # sudo apt-get remove -y nginx apache2 || true
        
        # Clean package caches
        sudo dnf clean all || true
        sudo yum clean all || true
        sudo apt-get autoremove -y || true
        sudo apt-get autoclean || true
    "
    
    print_status "Packages cleaned up"
}

# Final system cleanup
final_cleanup() {
    print_info "Performing final system cleanup..."
    
    run_remote "
        # Reload systemd
        sudo systemctl daemon-reload
        
        # Clear journal logs
        sudo journalctl --vacuum-time=1d || true
        
        # Clear temp directories
        sudo rm -rf /tmp/* || true
        sudo rm -rf /var/tmp/* || true
        
        # Clear bash history related to nopcommerce
        history -c || true
        
        # Update package lists
        sudo dnf makecache || true
        sudo yum makecache || true
        sudo apt-get update || true
    "
    
    print_status "Final cleanup completed"
}

# System status check
check_system_status() {
    print_info "Checking system status after cleanup..."
    
    run_remote "
        echo '=== System Status ==='
        uptime
        echo
        
        echo '=== Memory Usage ==='
        free -h
        echo
        
        echo '=== Disk Usage ==='
        df -h
        echo
        
        echo '=== Running Services ==='
        sudo systemctl list-units --type=service --state=running | grep -E 'nop|dotnet' || echo 'No nopCommerce related services running'
        echo
        
        echo '=== Open Ports ==='
        sudo netstat -tlnp | grep -E ':(80|443|5000|5001)' || echo 'Ports 80, 443, 5000, 5001 are free'
        echo
        
        echo '=== Docker Status ==='
        if command -v docker &> /dev/null; then
            sudo docker ps -a || echo 'No Docker containers'
        else
            echo 'Docker not installed'
        fi
    "
}

# Main execution
main() {
    echo "🧹 nopCommerce OCI VM Cleanup"
    echo "=============================="
    
    if [ "$OCI_IP" = "YOUR_OCI_IP_HERE" ]; then
        print_error "Please update the OCI_IP variable in this script with your actual instance IP"
        exit 1
    fi
    
    check_connection
    
    echo ""
    echo "This will clean up ALL previous nopCommerce deployments on $OCI_IP"
    read -p "Are you sure you want to continue? (y/N): " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
    
    stop_services
    remove_files
    cleanup_docker
    reset_firewall
    remove_packages
    final_cleanup
    
    echo ""
    print_status "✨ OCI VM cleanup completed successfully!"
    print_info "The instance is now clean and ready for fresh deployment"
    
    echo ""
    check_system_status
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo "  --status      Check current system status only"
    echo ""
    echo "Before running, update these variables in the script:"
    echo "  OCI_IP        Your OCI instance IP address"
    echo "  SSH_KEY       Path to your SSH private key"
    echo "  SSH_USER      SSH username (usually 'opc')"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --status)
        check_connection
        check_system_status
        exit 0
        ;;
    *)
        main
        ;;
esac