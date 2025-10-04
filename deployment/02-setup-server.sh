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
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 9.0 --runtime aspnetcore --install-dir $HOME/.dotnet

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

# If the above fails, fallback to package manager with .NET 8.0
if ! /usr/local/bin/dotnet --version >/dev/null 2>&1; then
    print_warning ".NET 9.0 installation failed, trying package manager with .NET 8.0..."
    
    case $DISTRO in
        "ubuntu"|"debian")
            # Add Microsoft package repository
            curl -sSL https://packages.microsoft.com/keys/microsoft.asc | $SUDO gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
            
            if [ "$DISTRO" = "ubuntu" ]; then
                echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/repos/microsoft-ubuntu-jammy-prod jammy main" | $SUDO tee /etc/apt/sources.list.d/microsoft-prod.list
            fi
            
            $SUDO apt update
            # Try .NET 8.0, fallback to 6.0 if needed
            $INSTALL_CMD aspnetcore-runtime-8.0 dotnet-runtime-8.0 || {
                print_warning ".NET 8.0 not available, trying .NET 6.0..."
                $INSTALL_CMD aspnetcore-runtime-6.0 dotnet-runtime-6.0
            }
            ;;
        
        "centos"|"rhel"|"ol")
            # Add Microsoft repository
            $SUDO rpm -Uvh https://packages.microsoft.com/config/centos/8/packages-microsoft-prod.rpm || true
            
            if command -v dnf &> /dev/null; then
                $SUDO dnf install -y aspnetcore-runtime-8.0 dotnet-runtime-8.0
            else
                $SUDO yum install -y aspnetcore-runtime-8.0 dotnet-runtime-8.0
            fi
            ;;
        
        "fedora")
            $SUDO rpm -Uvh https://packages.microsoft.com/config/fedora/37/packages-microsoft-prod.rpm || true
            $SUDO dnf install -y aspnetcore-runtime-8.0 dotnet-runtime-8.0
            ;;
    esac
fi

# Verify .NET installation
print_status "Verifying .NET installation..."
if command -v dotnet &> /dev/null; then
    DOTNET_VERSION=$(dotnet --version)
    print_status ".NET version installed: $DOTNET_VERSION"
else
    print_error ".NET installation failed"
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
$SUDO systemctl start mysqld || $SUDO systemctl start mysql
$SUDO systemctl enable mysqld || $SUDO systemctl enable mysql

# Secure MySQL installation and setup
print_status "Setting up MySQL database and user..."

# Generate a strong password for MySQL
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_NOP_PASSWORD=$(openssl rand -base64 32)

# Save passwords to a secure file
$SUDO mkdir -p /root/nopcommerce
$SUDO cat > /root/nopcommerce/mysql-credentials.txt << EOF
MySQL Root Password: $MYSQL_ROOT_PASSWORD
nopCommerce DB User: nopuser
nopCommerce DB Password: $MYSQL_NOP_PASSWORD
nopCommerce Database: nopcommerce_prod
EOF

$SUDO chmod 600 /root/nopcommerce/mysql-credentials.txt

# Setup MySQL root password and create nopCommerce database
print_status "Configuring MySQL..."

# For systems that don't set a root password by default
$SUDO mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';" 2>/dev/null || {
    # If the above fails, try without password first
    $SUDO mysql << EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
}

# Create nopCommerce database and user
print_status "Creating nopCommerce database and user..."
$SUDO mysql -u root -p"$MYSQL_ROOT_PASSWORD" << EOF
CREATE DATABASE IF NOT EXISTS nopcommerce_prod CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'nopuser'@'localhost' IDENTIFIED BY '$MYSQL_NOP_PASSWORD';
GRANT ALL PRIVILEGES ON nopcommerce_prod.* TO 'nopuser'@'localhost';
FLUSH PRIVILEGES;
EOF

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
        $INSTALL_CMD htop iotop netstat-ss tree vim nano
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
$SUDO cat > /usr/local/bin/nopcommerce-maintenance << 'EOF'
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
$SUDO cat > /etc/logrotate.d/nopcommerce << 'EOF'
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
echo -e "• MySQL credentials saved to: ${BLUE}/root/nopcommerce/mysql-credentials.txt${NC}"
echo -e "• Maintenance script: ${BLUE}/usr/local/bin/nopcommerce-maintenance${NC}"
echo -e "• Application directory: ${BLUE}/var/www/nopcommerce${NC}"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo -e "1. Update the MySQL connection string with the generated password"
echo -e "2. Deploy the nopCommerce application files"
echo -e "3. Configure SSL certificate (recommended for production)"
echo -e "${BLUE}============================================================================${NC}"