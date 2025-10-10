#!/bin/bash

# nopCommerce Database Sync Script
# Supports bidirectional sync between Production (MySQL) and Development (SQL Server)
set -e

# Configuration
OCI_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

# Production Database (MySQL on OCI)
PROD_DB_HOST="localhost"
PROD_DB_NAME="nopcommerce_prod"
PROD_DB_USER="nopcommerce_user"
PROD_DB_PASS="nopCommerce_secure_2024"
PROD_ROOT_PASS="Veen@"

# Local Development Database (MySQL in Docker)  
DEV_DB_HOST="localhost"
DEV_DB_NAME="nopCommerce"
DEV_DB_USER="root"
DEV_DB_PASS="nopCommerce_db_password"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "${BLUE}$1${NC}"; }
print_action() { echo -e "${CYAN}→${NC} $1"; }

# Function to run remote commands on OCI
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && $1"
}

# Function to check if local development environment is running
check_local_dev() {
    print_info "Checking local development environment..."
    
    if ! docker ps | grep -q "nopcommerce_mysql_server"; then
        print_error "Local development database not running!"
        print_action "Starting local development environment..."
        
        cd /Users/majunu/PaisleyTech/VeenaCollections/nopCommerce
        docker-compose up -d
        
        print_info "Waiting for database to be ready..."
        sleep 30
    fi
    
    print_status "Local development environment is ready"
}

# Function to create backup directories
setup_backup_dirs() {
    mkdir -p ./db-backups/prod-to-dev
    mkdir -p ./db-backups/dev-to-prod
    print_status "Backup directories created"
}

# Function to sync Production → Development
sync_prod_to_dev() {
    print_header "🔄 Syncing Production → Development"
    print_header "===================================="
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="./db-backups/prod-to-dev/nopcommerce_prod_${timestamp}.sql"
    
    print_action "Step 1: Creating production database backup..."
    
    # Create MySQL dump on production server
    run_remote "
        echo 'Creating MySQL dump...'
        mysqldump -u $PROD_DB_USER -p'$PROD_DB_PASS' \
            --single-transaction \
            --routines \
            --triggers \
            --hex-blob \
            --default-character-set=utf8mb4 \
            --add-drop-table \
            --complete-insert \
            $PROD_DB_NAME > /tmp/nopcommerce_backup_${timestamp}.sql
        
        echo 'Production backup created: /tmp/nopcommerce_backup_${timestamp}.sql'
        ls -lh /tmp/nopcommerce_backup_${timestamp}.sql
    "
    
    print_action "Step 2: Downloading production backup..."
    
    # Download the backup file
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP:/tmp/nopcommerce_backup_${timestamp}.sql" "$backup_file"
    
    print_status "Backup downloaded: $(ls -lh "$backup_file" | awk '{print $5}')"
    
    print_action "Step 3: Preparing MySQL dump for import..."
    
    # Since both are MySQL, we can use the dump directly with minor modifications
    local converted_file="./db-backups/prod-to-dev/nopcommerce_ready_${timestamp}.sql"
    
    # Prepare the dump for import - change database name and add safety commands
    cat > "$converted_file" << EOF
-- nopCommerce Database Import from Production
-- Generated: $(date)
-- Source: $PROD_DB_NAME (Production)
-- Target: $DEV_DB_NAME (Development)

SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;

-- Use the development database
USE $DEV_DB_NAME;

-- Drop all existing tables
EOF
    
    # Add table dropping commands
    mysql -h localhost -P 3306 -u $DEV_DB_USER -p"$DEV_DB_PASS" -e "
        SELECT CONCAT('DROP TABLE IF EXISTS \`', table_name, '\`;') 
        FROM information_schema.tables 
        WHERE table_schema = '$DEV_DB_NAME';" -N >> "$converted_file"
    
    # Add the production data (skip CREATE DATABASE and USE statements)
    grep -v "^CREATE DATABASE\|^USE " "$backup_file" >> "$converted_file"
    
    # Add closing commands
    cat >> "$converted_file" << EOF

COMMIT;
SET FOREIGN_KEY_CHECKS = 1;
EOF
    
    print_status "MySQL dump prepared for local development import"
    
    print_action "Step 4: Importing to local development database..."
    
    # Check if local dev environment is ready
    check_local_dev
    
    # Import to MySQL development database
    print_info "Importing production data to local MySQL..."
    
    # Import the prepared MySQL dump
    mysql -h localhost -P 3306 -u $DEV_DB_USER -p"$DEV_DB_PASS" < "$converted_file"
    
    print_status "Production data imported to development database!"
    
    # Cleanup remote backup
    run_remote "rm -f /tmp/nopcommerce_backup_${timestamp}.sql"
    
    print_status "🎉 Production → Development sync completed successfully!"
    print_info "Backup saved: $backup_file"
}

# Function to sync Development → Production  
sync_dev_to_prod() {
    print_header "⚠️  Syncing Development → Production"
    print_header "===================================="
    
    print_error "WARNING: This will overwrite your PRODUCTION database!"
    print_info "Production URL: http://$OCI_IP"
    echo
    read -p "Are you sure you want to continue? Type 'YES' to proceed: " confirm
    
    if [ "$confirm" != "YES" ]; then
        print_info "Operation cancelled."
        return 0
    fi
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="./db-backups/dev-to-prod/nopcommerce_dev_${timestamp}.sql"
    
    print_action "Step 1: Creating development database backup..."
    
    # Check if local dev environment is ready
    check_local_dev
    
    # Create SQL Server backup using sqlcmd
    print_info "Exporting from SQL Server development database..."
    
    # Note: SQL Server to MySQL migration is complex, this is a simplified version
    # For production use, consider using specialized migration tools
    
    docker exec nopcommerce-db /opt/mssql-tools/bin/sqlcmd -S localhost -U $DEV_DB_USER -P "$DEV_DB_PASS" -Q "
    BACKUP DATABASE $DEV_DB_NAME TO DISK = '/tmp/dev_backup_${timestamp}.bak'
    WITH FORMAT, COPY_ONLY;
    " > /dev/null 2>&1
    
    print_status "Development database backup created"
    
    print_action "Step 2: Creating production backup (safety)..."
    
    # Create safety backup of production before overwriting
    run_remote "
        echo 'Creating safety backup of production...'
        mysqldump -u $PROD_DB_USER -p'$PROD_DB_PASS' \
            --single-transaction \
            --routines \
            --triggers \
            $PROD_DB_NAME > /tmp/prod_safety_backup_${timestamp}.sql
        
        echo 'Production safety backup created'
    "
    
    print_action "Step 3: This feature requires advanced migration tools..."
    print_info "SQL Server → MySQL migration is complex and requires:"
    print_info "• Schema conversion (data types, constraints)"
    print_info "• Data transformation and encoding"
    print_info "• Index and foreign key recreation"
    
    print_error "For now, please use the Production → Development sync for testing."
    print_info "For deploying changes to production, use your deployment pipeline."
    
    print_info "Safety backup of production saved on server: /tmp/prod_safety_backup_${timestamp}.sql"
}

# Function to show sync status
show_status() {
    print_header "📊 Database Sync Status"
    print_header "======================"
    
    print_info "Production Database (MySQL):"
    echo "   • Host: $PROD_DB_HOST"
    echo "   • Database: $PROD_DB_NAME"
    echo "   • User: $PROD_DB_USER"
    echo "   • URL: http://$OCI_IP"
    
    print_info "Development Database (MySQL):"
    echo "   • Host: $DEV_DB_HOST"
    echo "   • Database: $DEV_DB_NAME" 
    echo "   • User: $DEV_DB_USER"
    echo "   • URL: http://localhost"
    
    print_info "Recent Backups:"
    if [ -d "./db-backups" ]; then
        find ./db-backups -name "*.sql" -type f -exec ls -lh {} \; | tail -5
    else
        echo "   No backups found"
    fi
}

# Function to cleanup old backups
cleanup_backups() {
    print_header "🧹 Cleaning Up Old Backups"
    print_header "=========================="
    
    if [ -d "./db-backups" ]; then
        # Keep last 5 backups of each type
        find ./db-backups -name "*.sql" -type f -mtime +7 -delete
        find ./db-backups -name "*.bak" -type f -mtime +7 -delete
        
        print_status "Old backups cleaned up (kept last 7 days)"
    else
        print_info "No backup directory found"
    fi
}

# Main menu
main_menu() {
    print_header "🔄 nopCommerce Database Sync Tool"
    print_header "================================="
    echo
    echo "Choose sync direction:"
    echo "1) Production → Development (MySQL → MySQL)"
    echo "2) Development → Production (MySQL → MySQL) [Advanced]"
    echo "3) Show sync status"
    echo "4) Cleanup old backups" 
    echo "5) Exit"
    echo
    read -p "Enter your choice (1-5): " choice
    
    case $choice in
        1)
            setup_backup_dirs
            sync_prod_to_dev
            ;;
        2)
            setup_backup_dirs
            sync_dev_to_prod
            ;;
        3)
            show_status
            ;;
        4)
            cleanup_backups
            ;;
        5)
            print_status "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid choice. Please try again."
            main_menu
            ;;
    esac
}

# Run main menu
main_menu