#!/bin/bash

# nopCommerce Docker Setup Script
# Based on official nopCommerce documentation

set -e

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

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed!"
        print_info "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop/"
        print_info "After installation, restart your terminal and run this script again."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed!"
        print_info "Docker Compose should come with Docker Desktop. Please check your installation."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running!"
        print_info "Please start Docker Desktop and try again."
        exit 1
    fi
    
    print_status "Docker is installed and running"
}

# Build from source (your custom code)
build_from_source() {
    print_info "Building nopCommerce from source code..."
    
    # Build the Docker image
    print_info "This may take several minutes on first run..."
    docker build -t nopcommerce .
    
    print_status "nopCommerce image built successfully"
    
    # Start the services
    print_info "Starting nopCommerce with database..."
    docker-compose up -d
    
    print_status "Services started!"
    print_info "nopCommerce will be available at: http://localhost"
    print_info "Database connection details:"
    print_info "  Server: nopcommerce_mssql_server"
    print_info "  User: sa"
    print_info "  Password: nopCommerce_db_password"
}

# Use official Docker Hub image
use_official_image() {
    print_info "Using official nopCommerce Docker image..."
    
    # Pull the official image
    print_info "Pulling official nopCommerce image..."
    docker pull nopcommerceteam/nopcommerce:latest
    
    print_status "Official image downloaded"
    
    # Start with official image
    print_info "Starting nopCommerce with official image..."
    docker-compose -f docker-compose.official.yml up -d
    
    print_status "Services started!"
    print_info "nopCommerce will be available at: http://localhost"
}

# Show status
show_status() {
    print_info "Container Status:"
    docker ps
    echo ""
    print_info "To view logs: docker-compose logs -f"
    print_info "To stop: docker-compose down"
}

# Wait for services and show final info
wait_for_services() {
    print_info "Waiting for services to start (this may take a minute)..."
    sleep 30
    
    echo ""
    print_status "Setup completed!"
    print_info "Access nopCommerce at: http://localhost"
    print_info ""
    print_info "Database connection details for installation:"
    print_info "  Server name: nopcommerce_mssql_server"
    print_info "  Database name: nopCommerce (will be created)"
    print_info "  Username: sa"
    print_info "  Password: nopCommerce_db_password"
    print_info ""
    print_info "Useful commands:"
    print_info "  View logs: docker-compose logs -f"
    print_info "  Stop services: docker-compose down"
    print_info "  Restart: docker-compose restart"
}

# Main menu
main() {
    echo "🛍️ nopCommerce Docker Setup"
    echo "==========================="
    
    check_docker
    
    echo ""
    echo "Choose setup method:"
    echo "1) Build from source (your custom code)"
    echo "2) Use official Docker Hub image (recommended for testing)"
    echo "3) Show current container status"
    echo "4) Stop all containers"
    echo ""
    
    read -p "Enter choice [1-4]: " choice
    
    case $choice in
        1)
            build_from_source
            wait_for_services
            ;;
        2)
            use_official_image
            wait_for_services
            ;;
        3)
            show_status
            ;;
        4)
            print_info "Stopping containers..."
            docker-compose down 2>/dev/null || true
            docker-compose -f docker-compose.official.yml down 2>/dev/null || true
            print_status "All containers stopped"
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

main "$@"