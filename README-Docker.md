# nopCommerce Docker Setup Guide

This guide follows the official nopCommerce Docker documentation and provides two approaches for running nopCommerce locally with Docker.

## Prerequisites

1. **Install Docker Desktop for macOS**
   - Download from: https://www.docker.com/products/docker-desktop/
   - Follow the installation instructions
   - Start Docker Desktop application

2. **Verify Installation**
   ```bash
   docker --version
   docker-compose --version
   ```

## Quick Start

### Option 1: Automated Setup (Recommended)

Run the setup script:
```bash
chmod +x setup-docker.sh
./setup-docker.sh
```

### Option 2: Manual Setup

#### Method A: Build from Source (Your Custom Code)

1. **Build the Docker image:**
   ```bash
   docker build -t nopcommerce .
   ```

2. **Start services:**
   ```bash
   docker-compose up -d
   ```

#### Method B: Use Official Docker Hub Image

1. **Pull official image:**
   ```bash
   docker pull nopcommerceteam/nopcommerce:latest
   ```

2. **Start with official image:**
   ```bash
   docker-compose -f docker-compose.official.yml up -d
   ```

## Accessing nopCommerce

- **URL:** http://localhost
- **Admin:** http://localhost/admin

## Database Configuration

During nopCommerce installation, use these database settings:

- **Server name:** `nopcommerce_mssql_server`
- **Database name:** `nopCommerce` (will be created automatically)
- **Username:** `sa`
- **Password:** `nopCommerce_db_password`
- **Trusted connection:** No
- **SQL Server authentication:** Yes

## Useful Commands

```bash
# View running containers
docker ps

# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Restart services
docker-compose restart

# Remove all containers and data (clean start)
docker-compose down -v
docker system prune -a

# Access database directly
docker exec -it nopcommerce_mssql_server /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P nopCommerce_db_password
```

## File Structure

```
nopCommerce/
├── Dockerfile                     # Build instructions
├── docker-compose.yml            # Build from source setup
├── docker-compose.official.yml   # Official image setup
├── setup-docker.sh              # Automated setup script
└── README-Docker.md              # This guide
```

## Troubleshooting

### Port 80 Already in Use
If port 80 is occupied, modify the ports in docker-compose.yml:
```yaml
ports:
  - "8080:80"  # Use port 8080 instead
```

### Container Won't Start
1. Check Docker Desktop is running
2. View logs: `docker-compose logs`
3. Ensure no port conflicts

### Database Connection Issues
1. Verify container is running: `docker ps`
2. Check database logs: `docker-compose logs nopcommerce_database`
3. Ensure firewall isn't blocking connections

### Performance Issues
- Allocate more resources to Docker Desktop (Settings > Resources)
- Close unnecessary applications
- Use official image instead of building from source

## Production Deployment

For production deployment to Oracle Cloud Infrastructure or other cloud providers:
1. Use the official Docker Hub image for better performance
2. Set up proper SSL certificates
3. Use external database service
4. Configure load balancing
5. Set up monitoring and logging

## Next Steps

Once you have nopCommerce running locally:
1. Complete the installation wizard
2. Test your customizations
3. Plan production deployment strategy
4. Set up CI/CD pipeline for automated deployments