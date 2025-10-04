#!/bin/bash

# ============================================================================
# nopCommerce Local Deployment Preparation Script
# ============================================================================
# This script prepares the nopCommerce application for deployment to Linux VM
# Run this script on your local macOS machine before deploying to the server
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
PUBLISH_DIR="$PROJECT_DIR/publish"
SERVER_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}nopCommerce Local Deployment Preparation${NC}"
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

# Check prerequisites
print_status "Checking prerequisites..."

# Check if .NET SDK is installed
if ! command -v dotnet &> /dev/null; then
    print_error ".NET SDK is not installed. Please install .NET 9.0 SDK first."
    exit 1
fi

# Check .NET version
DOTNET_VERSION=$(dotnet --version)
print_status "Found .NET SDK version: $DOTNET_VERSION"

# Check if SSH key exists and has correct permissions
if [ ! -f "$SSH_KEY" ]; then
    print_error "SSH key not found at $SSH_KEY"
    exit 1
fi

# Ensure correct permissions on SSH key
chmod 600 "$SSH_KEY"
print_status "SSH key permissions verified"

# Navigate to project directory
cd "$PROJECT_DIR/src"

# Clean previous builds
print_status "Cleaning previous builds..."
dotnet clean
rm -rf "$PUBLISH_DIR"
mkdir -p "$PUBLISH_DIR"

# Restore dependencies
print_status "Restoring NuGet packages..."
dotnet restore

# Build the solution
print_status "Building the solution..."
dotnet build --configuration Release --no-restore

# Publish the web application
print_status "Publishing the web application..."
dotnet publish "Presentation/Nop.Web/Nop.Web.csproj" \
    --configuration Release \
    --output "$PUBLISH_DIR" \
    --no-build \
    --verbosity normal

# Create production configuration
print_status "Creating production configuration..."
cat > "$PUBLISH_DIR/App_Data/appsettings.json" << 'EOF'
{
  "ConnectionStrings": {
    "ConnectionString": "Server=localhost;User ID=nopuser;Password=noppass;Database=nopcommerce_prod;Allow User Variables=True;Use XA Transactions=False",
    "DataProvider": "mysql",
    "SQLCommandTimeout": null,
    "WithNoLock": false,
    "Collation": null,
    "CharacterSet": null
  },
  "CacheConfig": {
    "DefaultCacheTime": 60,
    "LinqDisableQueryCache": false
  },
  "CommonConfig": {
    "DisplayFullErrorStack": false,
    "UserAgentStringsPath": "~/App_Data/browscap.xml",
    "CrawlerOnlyUserAgentStringsPath": "~/App_Data/browscap.crawlersonly.xml",
    "CrawlerOnlyAdditionalUserAgentStringsPath": "~/App_Data/additional.crawlers.xml",
    "UseSessionStateTempDataProvider": false,
    "ScheduleTaskRunTimeout": "",
    "StaticFilesCacheControl": "public,max-age=31536000",
    "ServeUnknownFileTypes": false,
    "UseAutofac": true,
    "PermitLimit": 0,
    "QueueCount": 0,
    "RejectionStatusCode": 503
  },
  "DistributedCacheConfig": {
    "DistributedCacheType": "memory",
    "Enabled": false,
    "ConnectionString": "",
    "SchemaName": "dbo",
    "TableName": "DistributedCache",
    "InstanceName": "nopCommerce",
    "PublishIntervalMs": 500
  },
  "HostingConfig": {
    "UseProxy": true,
    "ForwardedProtoHeaderName": "X-Forwarded-Proto",
    "ForwardedForHeaderName": "X-Forwarded-For",
    "KnownProxies": "",
    "KnownNetworks": ""
  },
  "InstallationConfig": {
    "DisableSampleData": false,
    "DisabledPlugins": "Misc.AzureBlob,Misc.CloudflareImages",
    "InstallRegionalResources": true
  },
  "PluginConfig": {
    "UseUnsafeLoadAssembly": true
  },
  "WebOptimizer": {
    "EnableJavaScriptBundling": true,
    "EnableCssBundling": true,
    "JavaScriptBundleSuffix": ".scripts",
    "CssBundleSuffix": ".styles",
    "EnableCaching": true,
    "EnableMemoryCache": true,
    "EnableDiskCache": true,
    "CacheDirectory": "/var/www/nopcommerce/wwwroot/bundles",
    "EnableTagHelperBundling": false,
    "CdnUrl": "",
    "AllowEmptyBundle": true,
    "HttpsCompression": 2,
    "MemoryCacheTimeToLive": "01:00:00"
  }
}
EOF

# Create deployment info file
print_status "Creating deployment info file..."
cat > "$PUBLISH_DIR/deployment-info.txt" << EOF
nopCommerce Deployment Information
==================================
Build Date: $(date)
Build Machine: $(hostname)
.NET Version: $DOTNET_VERSION
Git Branch: $(git branch --show-current 2>/dev/null || echo "Unknown")
Git Commit: $(git rev-parse HEAD 2>/dev/null || echo "Unknown")

Configuration:
- Database: MySQL
- Environment: Production
- Cache: Memory (Redis disabled for initial deployment)
EOF

# Create startup script for the server
print_status "Creating application startup script..."
cat > "$PUBLISH_DIR/start-nopcommerce.sh" << 'EOF'
#!/bin/bash

# nopCommerce Startup Script
cd /var/www/nopcommerce

# Set environment variables
export ASPNETCORE_ENVIRONMENT=Production
export ASPNETCORE_URLS="http://10.0.0.2:5000"

# Start the application
exec dotnet Nop.Web.dll
EOF

chmod +x "$PUBLISH_DIR/start-nopcommerce.sh"

# Create systemd service file
print_status "Creating systemd service file..."
cat > "$PUBLISH_DIR/nopcommerce.service" << 'EOF'
[Unit]
Description=nopCommerce E-commerce Platform
After=network.target
StartLimitIntervalSec=0

[Service]
Type=notify
Restart=always
RestartSec=1
User=www-data
WorkingDirectory=/var/www/nopcommerce
ExecStart=/usr/bin/dotnet /var/www/nopcommerce/Nop.Web.dll
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://10.0.0.2:5000
SyslogIdentifier=nopcommerce
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Create nginx configuration
print_status "Creating nginx configuration..."
cat > "$PUBLISH_DIR/nopcommerce.nginx.conf" << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Static files handling
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        root /var/www/nopcommerce/wwwroot;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # Handle static content
    location /content/ {
        root /var/www/nopcommerce/wwwroot;
        expires 30d;
        add_header Cache-Control "public";
    }
    
    location /bundles/ {
        root /var/www/nopcommerce/wwwroot;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Proxy to ASP.NET Core
    location / {
        proxy_pass http://10.0.0.2:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
        
        # Handle large uploads
        client_max_body_size 100m;
    }
}
EOF

# Create deployment archive
print_status "Creating deployment archive..."
cd "$PROJECT_DIR"
tar -czf "nopcommerce-deployment-$(date +%Y%m%d-%H%M%S).tar.gz" -C publish .

print_status "Local deployment preparation completed!"
print_status "Published files are in: $PUBLISH_DIR"
print_status "Deployment archive created: nopcommerce-deployment-*.tar.gz"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}Next Steps:${NC}"
echo -e "1. Run: ${YELLOW}./02-setup-server.sh${NC} to prepare the server"
echo -e "2. Run: ${YELLOW}./03-deploy-application.sh${NC} to deploy the application"
echo -e "${BLUE}============================================================================${NC}"