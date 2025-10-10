#!/bin/bash

# Simple nopCommerce Database Sync Script (MySQL to MySQL)
set -e

# Configuration
OCI_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

# Production Database (MySQL on OCI)
PROD_DB_NAME="nopcommerce_prod"
PROD_DB_USER="nopcommerce_user"
PROD_DB_PASS="nopCommerce_secure_2024"

# Local Development Database (MySQL in Docker)
DEV_DB_NAME="nopCommerce"
DEV_CONTAINER="nopcommerce_mysql_server"
DEV_ROOT_PASS="nopCommerce_db_password"

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

# Function to run remote commands
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && $1"
}

sync_prod_to_dev() {
    print_header "🔄 Syncing Production → Development"
    print_header "===================================="
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    
    # Step 1: Create backup directory
    mkdir -p ./db-backups
    
    print_info "Step 1: Creating production database backup..."
    
    # Create MySQL dump on production
    run_remote "
        mysqldump -u $PROD_DB_USER -p'$PROD_DB_PASS' \
            --single-transaction \
            --routines \
            --triggers \
            --hex-blob \
            --default-character-set=utf8mb4 \
            --complete-insert \
            --skip-lock-tables \
            $PROD_DB_NAME > /tmp/prod_backup_${timestamp}.sql
        
        echo 'Production backup size:'
        ls -lh /tmp/prod_backup_${timestamp}.sql
    "
    
    print_info "Step 2: Downloading backup..."
    
    # Download backup
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP:/tmp/prod_backup_${timestamp}.sql" "./db-backups/"
    
    local backup_file="./db-backups/prod_backup_${timestamp}.sql"
    print_status "Downloaded: $(ls -lh "$backup_file" | awk '{print $5}')"
    
    print_info "Step 3: Checking local development environment..."
    
    # Check if local MySQL is running
    if ! docker ps | grep -q "$DEV_CONTAINER"; then
        print_error "Local MySQL container not running!"
        print_info "Starting local development environment..."
        docker-compose up -d
        sleep 20
    fi
    
    print_info "Step 4: Importing to local development database..."
    
    # Import via Docker exec
    print_info "Dropping and recreating development database..."
    
    docker exec $DEV_CONTAINER mysql -u root -p"$DEV_ROOT_PASS" -e "
        DROP DATABASE IF EXISTS $DEV_DB_NAME;
        CREATE DATABASE $DEV_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        USE $DEV_DB_NAME;
    "
    
    print_info "Importing production data..."
    
    # Copy backup file into container and import
    docker cp "$backup_file" $DEV_CONTAINER:/tmp/
    
    docker exec $DEV_CONTAINER mysql -u root -p"$DEV_ROOT_PASS" $DEV_DB_NAME -e "SOURCE /tmp/prod_backup_${timestamp}.sql;"
    
    # Clean up container temp file
    docker exec $DEV_CONTAINER rm -f /tmp/prod_backup_${timestamp}.sql
    
    print_info "Step 5: Verifying import..."
    
    # Verify tables were imported
    local table_count=$(docker exec $DEV_CONTAINER mysql -u root -p"$DEV_ROOT_PASS" $DEV_DB_NAME -e "SHOW TABLES;" -s | wc -l | tr -d ' ')
    
    if [ "$table_count" -gt 0 ]; then
        print_status "✅ SUCCESS! Imported $table_count tables to local development"
        print_info "🌐 Local nopCommerce: http://localhost"
        print_info "📊 Production data synced to development environment"
        
        echo
        print_info "📋 Next Steps:"
        echo "   • Restart local nopCommerce: docker-compose restart"
        echo "   • Access at: http://localhost"
        echo "   • All production data is now available locally for development"
        
    else
        print_error "❌ Import may have failed - no tables found"
    fi
    
    # Cleanup
    run_remote "rm -f /tmp/prod_backup_${timestamp}.sql"
    
    print_status "🎯 Sync completed!"
}

show_status() {
    print_header "📊 Database Status"
    print_header "=================="
    
    print_info "Production (OCI MySQL):"
    echo "   • Database: $PROD_DB_NAME"
    echo "   • URL: http://$OCI_IP"
    
    print_info "Development (Local MySQL):"
    echo "   • Database: $DEV_DB_NAME" 
    echo "   • Container: $DEV_CONTAINER"
    echo "   • URL: http://localhost"
    
    print_info "Container Status:"
    if docker ps | grep -q "$DEV_CONTAINER"; then
        print_status "✅ Local MySQL container is running"
    else
        print_error "❌ Local MySQL container is not running"
    fi
    
    print_info "Recent Backups:"
    if [ -d "./db-backups" ]; then
        ls -lht ./db-backups/*.sql 2>/dev/null | head -3 || echo "   No backups found"
    else
        echo "   No backup directory"
    fi
}

main_menu() {
    print_header "🔄 nopCommerce Database Sync"
    print_header "============================"
    echo
    echo "Options:"
    echo "1) Sync Production → Development"
    echo "2) Show status"
    echo "3) Exit"
    echo
    read -p "Enter choice (1-3): " choice
    
    case $choice in
        1)
            sync_prod_to_dev
            ;;
        2)
            show_status
            ;;
        3)
            print_status "Done!"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            main_menu
            ;;
    esac
}

# Run
main_menu