# nopCommerce Deployment Guide for Oracle Cloud Infrastructure

## Overview

This guide provides comprehensive instructions for deploying your nopCommerce application from your local macOS development environment to an Oracle Cloud Infrastructure (OCI) Linux VM.

## Prerequisites

### Local Machine (macOS)
- .NET 9.0 SDK installed
- SSH access to your OCI VM
- Git (for version control)
- Terminal access

### Oracle Cloud VM
- Ubuntu 20.04/22.04 or CentOS/RHEL 8+ Linux VM
- Sudo privileges
- Internet connectivity
- At least 2GB RAM and 20GB storage

## Quick Start

If you want to deploy immediately, follow these steps:

1. **Make scripts executable:**
   ```bash
   chmod +x deployment/*.sh
   ```

2. **Prepare local deployment:**
   ```bash
   ./deployment/01-prepare-local.sh
   ```

3. **Setup server (run on your local machine, it will SSH to server):**
   ```bash
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 'bash -s' < deployment/02-setup-server.sh
   ```

4. **Deploy application:**
   ```bash
   ./deployment/03-deploy-application.sh
   ```

5. **Access your application:**
   - Primary URL: `https://theveenacollections.com`
   - Direct backend (for diagnostics without TLS): `http://129.146.167.43:5000`
   - Complete the nopCommerce installation wizard if this is the first run

## Detailed Step-by-Step Instructions

### Step 1: Prepare Local Environment

The `01-prepare-local.sh` script will:
- Build your nopCommerce solution
- Create a production-ready deployment package
- Generate configuration files for the server
- Create a compressed archive for deployment

**What it does:**
```bash
# Navigate to your project directory
cd /Users/majunu/PaisleyTech/VeenaCollections/nopCommerce

# Make the script executable
chmod +x deployment/01-prepare-local.sh

# Run the preparation script
./deployment/01-prepare-local.sh
```

**Output:** 
- Creates `publish/` directory with compiled application
- Generates `nopcommerce-deployment-YYYYMMDD-HHMMSS.tar.gz` archive
- Prepares production configuration files

### Step 2: Setup Oracle Cloud Server

The `02-setup-server.sh` script prepares your OCI VM with all necessary dependencies.

**Option A: Run directly on server**
```bash
# SSH to your server
ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43

# Copy and run the setup script
wget https://raw.githubusercontent.com/your-repo/deployment/02-setup-server.sh
chmod +x 02-setup-server.sh
sudo ./02-setup-server.sh
```

**Option B: Run from local machine (recommended)**
```bash
# This uploads and runs the script on the remote server
ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 'bash -s' < deployment/02-setup-server.sh
```

**What this installs:**
- .NET 9.0 Runtime and ASP.NET Core Runtime
- MySQL Server with secure configuration
- Nginx web server
- Firewall rules (ports 80, 443, 5000)
- System monitoring tools
- nopCommerce-specific directories and permissions

**Important:** The script generates secure MySQL passwords and saves them to `/root/nopcommerce/mysql-credentials.txt` on the server.

### Step 3: Deploy Application

The `03-deploy-application.sh` script transfers your application and configures it on the server.

```bash
# Ensure you've completed Steps 1 and 2 first
./deployment/03-deploy-application.sh
```

**What it does:**
- Transfers the deployment archive to the server
- Extracts files to `/var/www/nopcommerce/`
- Updates database connection strings with generated passwords
- Configures and starts systemd service
- Configures Nginx reverse proxy
- Sets appropriate file permissions
- Starts the application

### Step 4: Complete nopCommerce Installation

1. **Open your browser and navigate to:**
   ```
   http://129.146.167.43
   ```

2. **Follow the installation wizard:**
   - Choose your store information
   - Database is already configured (MySQL)
   - Create your admin account
   - Configure initial settings

3. **Database connection details** (pre-configured):
   - Server: `localhost`
   - Database: `nopcommerce_prod`
   - Username: `nopuser`
   - Password: (automatically generated and configured)

## Configuration Files

### Application Configuration (`appsettings.json`)
The deployment creates a production-ready configuration with:
- MySQL database connection
- Memory caching (Redis disabled initially)
- Production security settings
- Optimized web server settings

### Nginx Configuration
- Reverse proxy to ASP.NET Core app
- Static file serving optimization
- Security headers
- Gzip compression
- Large file upload support

### Systemd Service
- Automatic startup on boot
- Service monitoring and restart
- Proper logging configuration
- Environment variable management

## Server Management

### Maintenance Commands
The deployment installs a management script at `/usr/local/bin/nopcommerce-maintenance`:

```bash
# Check service status
sudo nopcommerce-maintenance status

# Start/stop/restart services
sudo nopcommerce-maintenance start
sudo nopcommerce-maintenance stop
sudo nopcommerce-maintenance restart

# View application logs
sudo nopcommerce-maintenance logs

# Create database backup
sudo nopcommerce-maintenance backup-db
```

### Manual Service Management
```bash
# Check nopCommerce service
sudo systemctl status nopcommerce

# Check application logs
sudo journalctl -u nopcommerce -f

# Check Nginx status
sudo systemctl status nginx

# Check MySQL status
sudo systemctl status mysql
```

### File Locations
- **Application:** `/var/www/nopcommerce/`
- **Configuration:** `/var/www/nopcommerce/App_Data/appsettings.json`
- **Logs:** `/var/www/nopcommerce/Logs/`
- **Nginx Config:** `/etc/nginx/sites-available/nopcommerce`
- **Service File:** `/etc/systemd/system/nopcommerce.service`
- **MySQL Credentials:** `/root/nopcommerce/mysql-credentials.txt`

## Troubleshooting

### Common Issues and Solutions

#### 1. Application Won't Start
```bash
# Check service status
sudo systemctl status nopcommerce

# View detailed logs
sudo journalctl -u nopcommerce -n 50

# Check if port 5000 is available
sudo netstat -tlnp | grep :5000
```

#### 2. Database Connection Issues
```bash
# Verify MySQL is running
sudo systemctl status mysql

# Check database exists
mysql -u nopuser -p -e "SHOW DATABASES;"

# Verify connection string in config
sudo cat /var/www/nopcommerce/App_Data/appsettings.json | grep ConnectionString
```

#### 3. Permission Issues
```bash
# Fix file permissions
sudo chown -R www-data:www-data /var/www/nopcommerce/
sudo chmod -R 755 /var/www/nopcommerce/
sudo chmod 644 /var/www/nopcommerce/App_Data/appsettings.json
```

#### 4. Nginx Issues
```bash
# Test Nginx configuration
sudo nginx -t

# Check Nginx status
sudo systemctl status nginx

# View Nginx error logs
sudo tail -f /var/log/nginx/error.log
```

#### 5. Firewall Issues
```bash
# Check if ports are open
sudo ss -tlnp | grep -E ':80|:443|:5000'

# For UFW (Ubuntu)
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# For firewalld (CentOS/RHEL)
sudo firewall-cmd --list-ports
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload
```

### Performance Optimization

#### 1. Enable Response Compression
Already configured in the nginx setup with gzip compression.

#### 2. Database Optimization
```sql
-- Connect to MySQL as nopuser
mysql -u nopuser -p nopcommerce_prod

-- Add indexes for common queries (after installation)
-- These will be created by nopCommerce, but you can monitor performance
SHOW PROCESSLIST;
SHOW ENGINE INNODB STATUS;
```

#### 3. Memory Usage
```bash
# Monitor memory usage
free -h
htop

# Adjust MySQL settings if needed
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
```

### HTTPS Reverse Proxy Setup (Nginx + Certbot)

1. **Upload the curated nginx site definition and enable it**
   ```bash
   scp -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key \
       deployment/nginx/nopcommerce.conf \
       ubuntu@129.146.167.43:/tmp/

   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 <<'EOF'
   /usr/bin/sudo /bin/mv /tmp/nopcommerce.conf /etc/nginx/sites-available/nopcommerce.conf
   /usr/bin/sudo /bin/mkdir -p /var/www/letsencrypt
   /usr/bin/sudo /bin/chown -R www-data:www-data /var/www/letsencrypt
   /usr/bin/sudo /bin/ln -sf /etc/nginx/sites-available/nopcommerce.conf /etc/nginx/sites-enabled/nopcommerce.conf
   /usr/bin/sudo /bin/rm -f /etc/nginx/sites-enabled/default
   /usr/bin/sudo /usr/sbin/nginx -t
   /usr/bin/sudo /usr/bin/systemctl reload nginx
   EOF
   ```
   The virtual host listens on port 80/443 and proxies to the Kestrel listener on `http://127.0.0.1:5000`.

2. **Install Certbot via snap (recommended by Let’s Encrypt)**
   ```bash
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 <<'EOF'
   /usr/bin/sudo /usr/bin/snap install core
   /usr/bin/sudo /usr/bin/snap refresh core
   /usr/bin/sudo /usr/bin/snap install --classic certbot
   /usr/bin/sudo /bin/ln -sf /snap/bin/certbot /usr/bin/certbot
   EOF
   ```

3. **Request certificates and enable HTTP→HTTPS redirects**
   ```bash
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 \
     '/usr/bin/sudo /usr/bin/certbot --nginx \
        -d theveenacollections.com -d www.theveenacollections.com \
        --non-interactive --agree-tos -m majunu@paisleytech.com --redirect'
   ```

4. **Validation**
   ```bash
   # From the server (hairpin-safe)
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 \
     '/usr/bin/curl -I --resolve theveenacollections.com:443:127.0.0.1 https://theveenacollections.com'

   # From your workstation (requires corporate proxy to allow the domain)
   curl -I https://theveenacollections.com
   ```

Certbot installs a systemd timer that renews the certificates automatically; no extra cron work is necessary.

### Backup Strategy

#### 1. Google Drive Database Backups (Service Account)
`deployment/nopcommerce-db-backup.sh` now dumps the MySQL database, gzips it, stores the archive under `/home/ubuntu/nopcommerce-db-backups`, and synchronises it to Google Drive via `rclone` using a Workspace service account. The script keeps only the three most recent dumps both locally and remotely.

1. **Upload the service-account JSON to the server:**
   ```bash
   scp -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key \
       ~/Downloads/veenacollections-*.json \
       ubuntu@129.146.167.43:/home/ubuntu/veenacollections-service-account.json
   ```

2. **Create or refresh the rclone remote:**
   ```bash
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 <<'EOF'
   export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
   mkdir -p ~/.config/rclone
   rclone config delete gdrive_nopcommerce >/dev/null 2>&1 || true
   rclone config create gdrive_nopcommerce drive \
       service_account_file=/home/ubuntu/veenacollections-service-account.json \
       scope=drive
   EOF
   ```
   If you are targeting a Shared Drive, share it with the service-account email as **Content Manager** and then set the drive ID:
   ```bash
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 \
     'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && \
      rclone config update gdrive_nopcommerce team_drive YOUR_SHARED_DRIVE_ID'
   ```

3. **Copy the backup script to the server:**
   ```bash
   scp -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key \
       deployment/nopcommerce-db-backup.sh \
       ubuntu@129.146.167.43:/tmp/

   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 <<'EOF'
   mv /tmp/nopcommerce-db-backup.sh /home/ubuntu/nopcommerce-db-backup.sh
   chmod 750 /home/ubuntu/nopcommerce-db-backup.sh
   ln -sf /home/ubuntu/nopcommerce-db-backup.sh /home/ubuntu/.local/bin/nopcommerce-db-backup.sh
   EOF
   ```

4. **Run a manual backup:**
   ```bash
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 \
     'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:~/.local/bin && ~/nopcommerce-db-backup.sh'
   ```

5. **Verify outputs:**
   ```bash
   # Local archives on the server
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 \
     'ls -1 /home/ubuntu/nopcommerce-db-backups'

   # Remote copies on Google Drive
   ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 \
     'rclone ls gdrive_nopcommerce:nopcommerce/db'
   ```

#### 2. Automating Weekly Backups (optional)
After you confirm manual runs, enable the provided service/timer to trigger the script every Sunday at 02:00 UTC (with a 30-minute randomised delay).

```bash
scp -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key \
    deployment/systemd/nopcommerce-db-backup.{service,timer} \
    ubuntu@129.146.167.43:/tmp/

ssh -i /Users/majunu/PaisleyTech/OCI/ssh-key-2025-09-09.key ubuntu@129.146.167.43 <<'EOF'
sudo mv /tmp/nopcommerce-db-backup.service /etc/systemd/system/
sudo mv /tmp/nopcommerce-db-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nopcommerce-db-backup.timer
EOF

sudo systemctl list-timers | grep nopcommerce-db-backup
```

Edit `deployment/systemd/nopcommerce-db-backup.timer` if you want a different schedule.

#### 3. Application Backups
```bash
# Backup entire application
sudo tar -czf /var/backups/nopcommerce-app-$(date +%Y%m%d).tar.gz -C /var/www nopcommerce
```

### Monitoring

#### 1. System Resources
```bash
# CPU and Memory
htop

# Disk usage
df -h
du -sh /var/www/nopcommerce/

# Network connections
sudo netstat -tlnp
```

#### 2. Application Monitoring
```bash
# Real-time logs
sudo journalctl -u nopcommerce -f

# Check response times
curl -w "@/tmp/curl-format.txt" -o /dev/null -s http://localhost:5000/
```

## Updates and Maintenance

### Updating nopCommerce
1. Test updates in development environment first
2. Create full backup (database + files)
3. Run the deployment scripts again with updated code
4. Test thoroughly before directing traffic

### Regular Maintenance Tasks
- Weekly: Check logs and system resources
- Monthly: Update system packages, review backups
- Quarterly: Security audit, performance review

## Security Considerations

### Server Security
- Keep system packages updated
- Configure proper firewall rules
- Use strong passwords for database
- Regular security patches
- Monitor access logs

### Application Security
- Use HTTPS in production (SSL certificate)
- Regular nopCommerce updates
- Strong admin passwords
- Regular security plugin updates
- Monitor for suspicious activity

## Support and Resources

### Log Files to Check
- Application: `sudo journalctl -u nopcommerce`
- Nginx: `/var/log/nginx/error.log`
- MySQL: `/var/log/mysql/error.log`
- System: `/var/log/syslog`

### Useful Commands for Debugging
```bash
# Check all services
sudo systemctl list-units --type=service --state=running | grep -E 'nginx|mysql|nopcommerce'

# Network connectivity
curl -I http://localhost:5000
curl -I http://129.146.167.43

# Process information
ps aux | grep -E 'dotnet|nginx|mysql'
```

This completes your nopCommerce deployment guide. Your application should now be running successfully on your Oracle Cloud Infrastructure VM!