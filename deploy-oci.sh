#!/bin/bash

# NopCommerce OCI Deployment Script
# This script automates the deployment of nopCommerce to Oracle Cloud Infrastructure

set -e

echo "🚀 Starting nopCommerce OCI Deployment..."

# Configuration
APP_NAME="nopcommerce"
DOCKER_REGISTRY="oci-registry-region.ocir.io/tenancy/repository"
VERSION=$(date +%Y%m%d-%H%M%S)
INSTANCE_IP="your-oci-instance-ip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    command -v docker >/dev/null 2>&1 || { print_error "Docker is required but not installed. Aborting."; exit 1; }
    command -v docker-compose >/dev/null 2>&1 || { print_error "Docker Compose is required but not installed. Aborting."; exit 1; }
    
    if [ ! -f ".env" ]; then
        print_warning ".env file not found. Creating from template..."
        cp .env.example .env
        print_warning "Please edit .env file with your configuration before continuing."
        exit 1
    fi
    
    print_status "Prerequisites check passed"
}

# Build application
build_application() {
    print_status "Building nopCommerce application..."
    
    # Build the Docker image
    docker build -t ${APP_NAME}:${VERSION} .
    docker tag ${APP_NAME}:${VERSION} ${APP_NAME}:latest
    
    print_status "Application built successfully"
}

# Push to OCI Registry (optional)
push_to_registry() {
    if [ "$1" = "push" ]; then
        print_status "Pushing to OCI Registry..."
        
        # Login to OCI Registry (you'll need to configure this)
        # docker login oci-registry-region.ocir.io
        
        docker tag ${APP_NAME}:${VERSION} ${DOCKER_REGISTRY}/${APP_NAME}:${VERSION}
        docker tag ${APP_NAME}:${VERSION} ${DOCKER_REGISTRY}/${APP_NAME}:latest
        
        docker push ${DOCKER_REGISTRY}/${APP_NAME}:${VERSION}
        docker push ${DOCKER_REGISTRY}/${APP_NAME}:latest
        
        print_status "Images pushed to registry"
    fi
}

# Deploy locally or to OCI instance
deploy_application() {
    print_status "Deploying nopCommerce..."
    
    # Create necessary directories
    mkdir -p ssl backups
    
    if [ "$1" = "local" ]; then
        # Local deployment
        docker-compose -f docker-compose.production.yml up -d
    else
        # Remote deployment to OCI instance
        print_status "Deploying to OCI instance: $INSTANCE_IP"
        
        # Copy files to remote server
        scp -r . opc@${INSTANCE_IP}:/home/opc/nopcommerce/
        
        # Execute deployment on remote server
        ssh opc@${INSTANCE_IP} << 'EOF'
            cd /home/opc/nopcommerce
            docker-compose -f docker-compose.production.yml pull
            docker-compose -f docker-compose.production.yml up -d
            docker system prune -f
EOF
    fi
    
    print_status "Deployment completed"
}

# Setup SSL with Let's Encrypt
setup_ssl() {
    if [ "$1" = "ssl" ]; then
        print_status "Setting up SSL with Let's Encrypt..."
        
        # This would typically use certbot
        # docker run --rm -v ./ssl:/etc/letsencrypt certbot/certbot certonly --standalone -d your-domain.com
        
        print_warning "SSL setup requires manual configuration. Please refer to the documentation."
    fi
}

# Health check
health_check() {
    print_status "Performing health check..."
    
    sleep 30  # Wait for services to start
    
    if curl -f http://localhost:8080/health > /dev/null 2>&1; then
        print_status "Application is healthy and running"
    else
        print_error "Health check failed. Please check the logs."
        docker-compose -f docker-compose.production.yml logs
        exit 1
    fi
}

# Backup database
backup_database() {
    print_status "Creating database backup..."
    
    BACKUP_FILE="backups/nopcommerce-backup-$(date +%Y%m%d-%H%M%S).sql"
    
    docker-compose -f docker-compose.production.yml exec -T nopcommerce_database \
        /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "${DB_PASSWORD}" \
        -Q "BACKUP DATABASE [nopCommerce] TO DISK = '/tmp/backup.bak'" \
        > /dev/null 2>&1
    
    docker cp nopcommerce_database:/tmp/backup.bak ${BACKUP_FILE}
    
    print_status "Database backup created: ${BACKUP_FILE}"
}

# Cleanup old backups
cleanup_backups() {
    print_status "Cleaning up old backups..."
    find backups/ -name "*.sql" -mtime +7 -delete
    print_status "Old backups cleaned up"
}

# Main deployment function
main() {
    case ${1:-deploy} in
        "build")
            check_prerequisites
            build_application
            ;;
        "deploy")
            check_prerequisites
            build_application
            deploy_application ${2:-local}
            health_check
            ;;
        "deploy-oci")
            check_prerequisites
            build_application
            push_to_registry push
            deploy_application remote
            setup_ssl ssl
            health_check
            ;;
        "backup")
            backup_database
            cleanup_backups
            ;;
        "logs")
            docker-compose -f docker-compose.production.yml logs -f
            ;;
        "stop")
            docker-compose -f docker-compose.production.yml down
            ;;
        "restart")
            docker-compose -f docker-compose.production.yml restart
            ;;
        "update")
            check_prerequisites
            backup_database
            build_application
            deploy_application ${2:-local}
            health_check
            ;;
        *)
            echo "Usage: $0 {build|deploy|deploy-oci|backup|logs|stop|restart|update}"
            echo ""
            echo "Commands:"
            echo "  build       - Build the application only"
            echo "  deploy      - Deploy locally (default)"
            echo "  deploy-oci  - Deploy to OCI instance with SSL"
            echo "  backup      - Backup database"
            echo "  logs        - View application logs"
            echo "  stop        - Stop all services"
            echo "  restart     - Restart all services"
            echo "  update      - Update deployment with backup"
            echo ""
            echo "Examples:"
            echo "  $0 deploy local     - Deploy locally"
            echo "  $0 deploy-oci       - Deploy to OCI"
            echo "  $0 update local     - Update local deployment"
            exit 1
            ;;
    esac
}

main "$@"