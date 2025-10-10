#!/bin/bash

# Enhanced nopCommerce Database Sync Script (Bidirectional)
set -e

# Configuration
OCI_IP="129.146.167.43"
SSH_KEY="/Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key"
SSH_USER="ubuntu"

# Production Database (MySQL on OCI)
PROD_DB_NAME="nopcommerce_prod"
PROD_DB_USER="nopcommerce_user"
PROD_DB_PASS="nopCommerce_secure_2024"
PROD_ROOT_PASS="Veen@"

# Local Development Database (MySQL in Docker)
DEV_DB_NAME="nopCommerce"
DEV_CONTAINER="nopcommerce_mysql_server"
DEV_ROOT_PASS="nopCommerce_db_password"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${YELLOW}ℹ${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_header() { echo -e "${BLUE}$1${NC}"; }
print_warning() { echo -e "${PURPLE}⚠️${NC} $1"; }
print_action() { echo -e "${CYAN}→${NC} $1"; }

# Function to run remote commands
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP" "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && $1"
}

# Function: Production → Development
sync_prod_to_dev() {
    print_header "🔄 Syncing Production → Development"
    print_header "===================================="
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    mkdir -p ./db-backups/prod-to-dev
    
    print_action "Step 1: Creating production backup..."
    
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
    
    print_action "Step 2: Downloading backup..."
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP:/tmp/prod_backup_${timestamp}.sql" "./db-backups/prod-to-dev/"
    
    local backup_file="./db-backups/prod-to-dev/prod_backup_${timestamp}.sql"
    print_status "Downloaded: $(ls -lh "$backup_file" | awk '{print $5}')"
    
    print_action "Step 3: Checking local environment..."
    if ! docker ps | grep -q "$DEV_CONTAINER"; then
        print_info "Starting local development environment..."
        docker-compose up -d
        sleep 20
    fi
    
    print_action "Step 4: Importing to development..."
    docker exec $DEV_CONTAINER mysql -u root -p"$DEV_ROOT_PASS" -e "
        DROP DATABASE IF EXISTS $DEV_DB_NAME;
        CREATE DATABASE $DEV_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    "
    
    docker cp "$backup_file" $DEV_CONTAINER:/tmp/
    docker exec $DEV_CONTAINER mysql -u root -p"$DEV_ROOT_PASS" $DEV_DB_NAME -e "SOURCE /tmp/prod_backup_${timestamp}.sql;"
    docker exec $DEV_CONTAINER rm -f /tmp/prod_backup_${timestamp}.sql
    
    local table_count=$(docker exec $DEV_CONTAINER mysql -u root -p"$DEV_ROOT_PASS" $DEV_DB_NAME -e "SHOW TABLES;" -s | wc -l | tr -d ' ')
    
    if [ "$table_count" -gt 0 ]; then
        print_status "✅ SUCCESS! Synced $table_count tables to development"
        print_info "🌐 Local nopCommerce: http://localhost"
        print_info "📊 Restart local app: docker-compose restart"
    else
        print_error "❌ Sync failed - no tables found"
    fi
    
    run_remote "rm -f /tmp/prod_backup_${timestamp}.sql"
    print_status "🎯 Production → Development sync completed!"
}

# Function: Development → Production (DANGEROUS)
sync_dev_to_prod() {
    print_header "⚠️  Syncing Development → Production"
    print_header "====================================="
    
    print_warning "🚨 DANGER: This will OVERWRITE your PRODUCTION database!"
    print_warning "🌐 Production URL: http://$OCI_IP"
    print_warning "👥 This affects your live users and data!"
    echo
    print_info "💡 Recommended: Test changes locally first with prod data"
    print_info "🔄 Use 'Production → Development' to get latest data for testing"
    echo
    
    read -p "❓ Are you absolutely sure? Type 'OVERWRITE PRODUCTION' to continue: " confirm
    
    if [ "$confirm" != "OVERWRITE PRODUCTION" ]; then
        print_info "✅ Operation cancelled - production data is safe"
        return 0
    fi
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    mkdir -p ./db-backups/dev-to-prod
    
    print_action "Step 1: Creating SAFETY backup of production..."
    
    # Create production safety backup
    run_remote "
        echo 'Creating production safety backup...'
        mysqldump -u $PROD_DB_USER -p'$PROD_DB_PASS' \
            --single-transaction \
            --routines \
            --triggers \
            --hex-blob \
            --default-character-set=utf8mb4 \
            --complete-insert \
            --skip-lock-tables \
            $PROD_DB_NAME > /tmp/prod_safety_${timestamp}.sql
        
        echo 'Production safety backup created:'
        ls -lh /tmp/prod_safety_${timestamp}.sql
    "
    
    # Download safety backup
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$OCI_IP:/tmp/prod_safety_${timestamp}.sql" "./db-backups/dev-to-prod/"
    print_status "Production safety backup downloaded"
    
    print_action "Step 2: Creating development backup..."
    
    # Check local environment
    if ! docker ps | grep -q "$DEV_CONTAINER"; then
        print_error "Local development container not running!"
        return 1
    fi
    
    # Create development backup
    docker exec $DEV_CONTAINER mysqldump -u root -p"$DEV_ROOT_PASS" \
        --single-transaction \
        --routines \
        --triggers \
        --hex-blob \
        --default-character-set=utf8mb4 \
        --complete-insert \
        --skip-lock-tables \
        $DEV_DB_NAME > "./db-backups/dev-to-prod/dev_backup_${timestamp}.sql"
    
    local dev_backup="./db-backups/dev-to-prod/dev_backup_${timestamp}.sql"
    print_status "Development backup created: $(ls -lh "$dev_backup" | awk '{print $5}')"
    
    print_action "Step 3: Uploading development data to production server..."
    
    # Upload dev backup to production server
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$dev_backup" "$SSH_USER@$OCI_IP:/tmp/"
    
    print_action "Step 4: Importing development data to production..."
    
    # Import development data to production
    run_remote "
        echo 'Dropping and recreating production database...'
        mysql -u root -p'$PROD_ROOT_PASS' -e \"
            DROP DATABASE IF EXISTS $PROD_DB_NAME;
            CREATE DATABASE $PROD_DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
            GRANT ALL PRIVILEGES ON $PROD_DB_NAME.* TO '$PROD_DB_USER'@'localhost';
            FLUSH PRIVILEGES;
        \"
        
        echo 'Importing development data...'
        mysql -u $PROD_DB_USER -p'$PROD_DB_PASS' $PROD_DB_NAME < /tmp/dev_backup_${timestamp}.sql
        
        echo 'Verifying import...'
        table_count=\$(mysql -u $PROD_DB_USER -p'$PROD_DB_PASS' $PROD_DB_NAME -e 'SHOW TABLES;' -s | wc -l)
        echo \"Imported \$table_count tables to production\"
        
        # Cleanup
        rm -f /tmp/dev_backup_${timestamp}.sql
    "
    
    print_action "Step 5: Restarting production application..."
    
    # Restart production nopCommerce
    run_remote "
        cd /home/ubuntu
        docker-compose -f docker-compose.network-fixed.yml restart
        sleep 10
        
        echo 'Production application restarted'
        docker ps
    "
    
    print_status "✅ Development → Production sync completed!"
    
    print_header "📋 Important Information"
    print_status "🌐 Production URL: http://$OCI_IP"
    print_status "💾 Production safety backup: ./db-backups/dev-to-prod/prod_safety_${timestamp}.sql"
    print_info "🔄 If you need to rollback, use the safety backup"
    
    print_warning "🧪 Test your production site now to ensure everything works!"
}

# Show status
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
        
        # Show recent changes in dev database
        local dev_tables=$(docker exec $DEV_CONTAINER mysql -u root -p"$DEV_ROOT_PASS" $DEV_DB_NAME -e "SHOW TABLES;" -s | wc -l 2>/dev/null | tr -d ' ')
        print_info "📊 Development tables: $dev_tables"
    else
        print_error "❌ Local MySQL container is not running"
    fi
    
    print_info "Recent Backups:"
    if [ -d "./db-backups" ]; then
        echo "   Prod→Dev backups:"
        ls -lht ./db-backups/prod-to-dev/*.sql 2>/dev/null | head -2 | awk '{print "     " $9 " (" $5 ")"}' || echo "     None"
        echo "   Dev→Prod backups:"
        ls -lht ./db-backups/dev-to-prod/*.sql 2>/dev/null | head -2 | awk '{print "     " $9 " (" $5 ")"}' || echo "     None"
    else
        echo "   No backup directory"
    fi
}

# Main menu
main_menu() {
    print_header "🔄 nopCommerce Database Sync (Bidirectional)"
    print_header "============================================="
    echo
    print_info "Sync Options:"
    echo "1) 📥 Production → Development (Safe - get latest prod data)"
    echo "2) 📤 Development → Production (⚠️  DANGER - overwrites prod!)"
    echo "3) 📊 Show status and recent backups"
    echo "4) 🧹 Clean old backups"
    echo "5) ❌ Exit"
    echo
    read -p "Enter choice (1-5): " choice
    
    case $choice in
        1)
            sync_prod_to_dev
            ;;
        2)
            sync_dev_to_prod
            ;;
        3)
            show_status
            ;;
        4)
            print_info "Cleaning backups older than 7 days..."
            find ./db-backups -name "*.sql" -mtime +7 -delete 2>/dev/null || true
            print_status "Cleanup completed"
            ;;
        5)
            print_status "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            main_menu
            ;;
    esac
    
    echo
    read -p "Press Enter to return to menu..." 
    main_menu
}

# Check requirements
check_requirements() {
    if [ ! -f "$SSH_KEY" ]; then
        print_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker."
        exit 1
    fi
    
    if ! command -v ssh &> /dev/null; then
        print_error "SSH not found."
        exit 1
    fi
}

# Run
check_requirements
main_menu