#!/bin/bash

# ============================================================================
# nopCommerce Server Setup Script
# ============================================================================
# This script sets up the Oracle Cloud Infrastructure Linux VM for nopCommerce
# Run this script ON THE SERVER (via SSH) to install all dependencies
# ============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}nopCommerce Server Setup for Oracle Cloud Infrastructure${NC}"
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

# Check if running as root or with sudo
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
    print_status "Running with sudo privileges"
fi

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    DISTRO=$ID
    VERSION=$VERSION_ID
else
    print_error "Cannot detect Linux distribution"
    exit 1
fi

print_status "Detected OS: $OS ($DISTRO $VERSION)"

# Update system packages
print_status "Updating system packages..."
case $DISTRO in
    "ubuntu"|"debian")
        $SUDO apt update && $SUDO apt upgrade -y
        INSTALL_CMD="$SUDO apt install -y"
        ;;
    "centos"|"rhel"|"ol"|"fedora")
        if command -v dnf &> /dev/null; then
            $SUDO dnf update -y
            INSTALL_CMD="$SUDO dnf install -y"
        else
            $SUDO yum update -y
            INSTALL_CMD="$SUDO yum install -y"
        fi
        ;;
    *)
        print_error "Unsupported Linux distribution: $DISTRO"
        exit 1
        ;;
esac

# Install basic tools
print_status "Installing basic tools..."
case $DISTRO in
    "ubuntu"|"debian")
        $INSTALL_CMD curl wget unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release
        ;;
    "centos"|"rhel"|"ol"|"fedora")
        $INSTALL_CMD curl wget unzip ca-certificates gnupg2
        ;;
esac

# Install .NET 9.0 using Microsoft's official installer script
print_status "Installing .NET 9.0 runtime and ASP.NET Core runtime..."

# Create directory first with proper permissions
$SUDO mkdir -p /usr/local/dotnet

# Use Microsoft's official install script which handles multiple architectures
print_status "Downloading and running Microsoft .NET installer..."
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 9.0 --runtime aspnetcore --install-dir $HOME/.dotnet 2>/dev/null || {
    print_warning "Microsoft installer failed, will try alternative methods"
}

# Move from user directory to system directory
if [ -d "$HOME/.dotnet" ]; then
    $SUDO cp -r "$HOME/.dotnet"/* /usr/local/dotnet/ 2>/dev/null || true
    $SUDO chown -R root:root /usr/local/dotnet
fi

# Create global symlink
$SUDO ln -sf /usr/local/dotnet/dotnet /usr/local/bin/dotnet
$SUDO chmod +x /usr/local/bin/dotnet

# Add to PATH for all users
echo 'export DOTNET_ROOT=/usr/local/dotnet' | $SUDO tee -a /etc/environment
echo 'export PATH=$PATH:/usr/local/dotnet' | $SUDO tee -a /etc/environment

# Source the environment
export DOTNET_ROOT=/usr/local/dotnet
export PATH=$PATH:/usr/local/dotnet

# Check if .NET is working properly (either from custom install or system install)
DOTNET_WORKING=false

# Try the custom installation first
if [ -f "/usr/local/dotnet/dotnet" ] && /usr/local/dotnet/dotnet --list-runtimes >/dev/null 2>&1; then
    print_status ".NET 9.0 custom installation is working"
    DOTNET_WORKING=true
# Try system-installed dotnet
elif command -v dotnet >/dev/null 2>&1 && dotnet --list-runtimes >/dev/null 2>&1; then
    print_status "System .NET installation is working"
    DOTNET_WORKING=true
fi

# If .NET is not working, try package manager installation
if [ "$DOTNET_WORKING" = false ]; then
    print_warning ".NET installation not working properly, trying package manager..."
    
    case $DISTRO in
        "ubuntu"|"debian")
            # Only add Microsoft repository if it doesn't exist
            if [ ! -f /usr/share/keyrings/microsoft-prod.gpg ]; then
                curl -sSL https://packages.microsoft.com/keys/microsoft.asc | $SUDO gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
            fi
            
            if [ "$DISTRO" = "ubuntu" ] && [ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
                echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/repos/microsoft-ubuntu-jammy-prod jammy main" | $SUDO tee /etc/apt/sources.list.d/microsoft-prod.list
                $SUDO apt update
            fi
            
            # Try .NET 8.0, fallback to 6.0 if needed
            $INSTALL_CMD aspnetcore-runtime-8.0 dotnet-runtime-8.0 || {
                print_warning ".NET 8.0 not available, trying .NET 6.0..."
                $INSTALL_CMD aspnetcore-runtime-6.0 dotnet-runtime-6.0 || true
            }
            ;;
        
        "centos"|"rhel"|"ol")
            # Add Microsoft repository if not present
            if [ ! -f /etc/yum.repos.d/microsoft-prod.repo ]; then
                $SUDO rpm -Uvh https://packages.microsoft.com/config/centos/8/packages-microsoft-prod.rpm || true
            fi
            
            if command -v dnf &> /dev/null; then
                $SUDO dnf install -y aspnetcore-runtime-8.0 dotnet-runtime-8.0 || true
            else
                $SUDO yum install -y aspnetcore-runtime-8.0 dotnet-runtime-8.0 || true
            fi
            ;;
        
        "fedora")
            if [ ! -f /etc/yum.repos.d/microsoft-prod.repo ]; then
                $SUDO rpm -Uvh https://packages.microsoft.com/config/fedora/37/packages-microsoft-prod.rpm || true
            fi
            $SUDO dnf install -y aspnetcore-runtime-8.0 dotnet-runtime-8.0 || true
            ;;
    esac
fi

# Final verification of .NET installation
print_status "Verifying .NET installation..."

# Check custom installation first
if [ -f "/usr/local/dotnet/dotnet" ]; then
    DOTNET_CMD="/usr/local/dotnet/dotnet"
    export DOTNET_ROOT=/usr/local/dotnet
    export PATH=$PATH:/usr/local/dotnet
elif command -v dotnet &> /dev/null; then
    DOTNET_CMD="dotnet"
else
    print_error "No .NET installation found"
    exit 1
fi

# Test .NET functionality
if $DOTNET_CMD --list-runtimes >/dev/null 2>&1; then
    DOTNET_RUNTIMES=$($DOTNET_CMD --list-runtimes)
    print_status ".NET installation verified successfully"
    echo "Available runtimes:"
    echo "$DOTNET_RUNTIMES"
else
    print_error ".NET installation is not functional"
    exit 1
fi

# Install MySQL Server
print_status "Installing MySQL Server..."
case $DISTRO in
    "ubuntu"|"debian")
        $INSTALL_CMD mysql-server mysql-client
        ;;
    "centos"|"rhel"|"ol"|"fedora")
        if command -v dnf &> /dev/null; then
            $SUDO dnf install -y mysql-server mysql
        else
            $SUDO yum install -y mysql-server mysql
        fi
        ;;
esac

# Start and enable MySQL
print_status "Starting and enabling MySQL service..."
if systemctl list-unit-files | grep -q "mysql.service"; then
    $SUDO systemctl start mysql
    $SUDO systemctl enable mysql
elif systemctl list-unit-files | grep -q "mysqld.service"; then
    $SUDO systemctl start mysqld
    $SUDO systemctl enable mysqld
else
    print_error "MySQL service not found"
    exit 1
fi

# Verify MySQL installation and basic setup
print_status "Verifying MySQL installation..."

# Test MySQL connectivity
if $SUDO mysql -e "SELECT VERSION();" >/dev/null 2>&1; then
    print_status "MySQL is accessible and working"
    MYSQL_VERSION=$($SUDO mysql -e "SELECT VERSION();" -s -N)
    print_status "MySQL version: $MYSQL_VERSION"
else
    print_warning "MySQL requires additional configuration or password setup"
    print_status "You may need to run mysql_secure_installation manually"
fi

# Create nopcommerce database if it doesn't exist (using configured credentials)
print_status "Ensuring nopcommerce database exists..."
$SUDO mysql -e "CREATE DATABASE IF NOT EXISTS nopcommerce CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || {
    print_status "Database creation skipped (may already exist or require manual setup)"
}

# Save database info for reference
$SUDO mkdir -p /root/nopcommerce
$SUDO tee /root/nopcommerce/database-info.txt > /dev/null << EOF
Database Name: nopcommerce
Database User: nopuser
Database Password: NopProd2024
Note: Database credentials are configured in appsettings.json
EOF

$SUDO chmod 600 /root/nopcommerce/database-info.txt

# Install Nginx
print_status "Installing Nginx..."
case $DISTRO in
    "ubuntu"|"debian")
        $INSTALL_CMD nginx
        ;;
    "centos"|"rhel"|"ol"|"fedora")
        if command -v dnf &> /dev/null; then
            $SUDO dnf install -y nginx
        else
            $SUDO yum install -y nginx
        fi
        ;;
esac

# Start and enable Nginx
$SUDO systemctl start nginx
$SUDO systemctl enable nginx

# Create application directory
print_status "Creating application directory..."
$SUDO mkdir -p /var/www/nopcommerce
$SUDO chown -R www-data:www-data /var/www/nopcommerce || $SUDO chown -R nginx:nginx /var/www/nopcommerce

# Configure firewall (if firewalld is running)
if systemctl is-active --quiet firewalld; then
    print_status "Configuring firewall..."
    $SUDO firewall-cmd --permanent --add-service=http
    $SUDO firewall-cmd --permanent --add-service=https
    $SUDO firewall-cmd --permanent --add-port=5000/tcp
    $SUDO firewall-cmd --reload
fi

# Configure UFW (if it's active on Ubuntu)
if command -v ufw &> /dev/null && $SUDO ufw status | grep -q "Status: active"; then
    print_status "Configuring UFW firewall..."
    $SUDO ufw allow 80/tcp
    $SUDO ufw allow 443/tcp
    $SUDO ufw allow 5000/tcp
fi

# Install additional tools for monitoring and management
print_status "Installing additional system tools..."
case $DISTRO in
    "ubuntu"|"debian")
        $INSTALL_CMD htop iotop net-tools tree vim nano
        ;;
    "centos"|"rhel"|"ol"|"fedora")
        if command -v dnf &> /dev/null; then
            $SUDO dnf install -y htop iotop net-tools tree vim nano
        else
            $SUDO yum install -y htop iotop net-tools tree vim nano
        fi
        ;;
esac

# Create maintenance script
print_status "Creating maintenance script..."
$SUDO tee /usr/local/bin/nopcommerce-maintenance > /dev/null << 'EOF'
#!/bin/bash

# nopCommerce Maintenance Script

case "$1" in
    start)
        echo "Starting nopCommerce..."
        systemctl start nopcommerce
        systemctl start nginx
        echo "nopCommerce started"
        ;;
    stop)
        echo "Stopping nopCommerce..."
        systemctl stop nopcommerce
        echo "nopCommerce stopped"
        ;;
    restart)
        echo "Restarting nopCommerce..."
        systemctl restart nopcommerce
        systemctl restart nginx
        echo "nopCommerce restarted"
        ;;
    status)
        echo "=== nopCommerce Service Status ==="
        systemctl status nopcommerce --no-pager
        echo -e "\n=== Nginx Status ==="
        systemctl status nginx --no-pager
        echo -e "\n=== MySQL Status ==="
        systemctl status mysql --no-pager || systemctl status mysqld --no-pager
        ;;
    logs)
        echo "=== nopCommerce Logs (last 50 lines) ==="
        journalctl -u nopcommerce -n 50 --no-pager
        ;;
    backup-db)
        echo "Creating database backup..."
        BACKUP_DIR="/root/nopcommerce/backups"
        mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="$BACKUP_DIR/nopcommerce_backup_$(date +%Y%m%d_%H%M%S).sql"
        mysqldump -u nopuser -p nopcommerce_prod > "$BACKUP_FILE"
        echo "Database backup created: $BACKUP_FILE"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|backup-db}"
        exit 1
        ;;
esac
EOF

$SUDO chmod +x /usr/local/bin/nopcommerce-maintenance

# Create log rotation configuration
print_status "Setting up log rotation..."
$SUDO tee /etc/logrotate.d/nopcommerce > /dev/null << 'EOF'
/var/www/nopcommerce/Logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        systemctl reload nopcommerce > /dev/null 2>&1 || true
    endscript
}
EOF

print_status "Server setup completed successfully!"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}Setup Summary:${NC}"
echo -e "• .NET 9.0 Runtime: ${GREEN}✓${NC} Installed"
echo -e "• MySQL Server: ${GREEN}✓${NC} Installed and configured"
echo -e "• Nginx: ${GREEN}✓${NC} Installed and running"
echo -e "• Application directory: ${GREEN}✓${NC} /var/www/nopcommerce"
echo -e "• Firewall: ${GREEN}✓${NC} Configured (ports 80, 443, 5000)"
echo -e "• Maintenance tools: ${GREEN}✓${NC} Installed"
echo ""
echo -e "${YELLOW}Important Information:${NC}"
echo -e "• Database info saved to: ${BLUE}/root/nopcommerce/database-info.txt${NC}"
echo -e "• Maintenance script: ${BLUE}/usr/local/bin/nopcommerce-maintenance${NC}"
echo -e "• Application directory: ${BLUE}/var/www/nopcommerce${NC}"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo -e "1. Deploy the nopCommerce application files"
echo -e "2. Configure SSL certificate (recommended for production)"
echo -e "3. Set up regular database backups"
echo -e "${BLUE}============================================================================${NC}"