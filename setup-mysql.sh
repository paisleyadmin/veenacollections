#!/bin/bash

# Setup MySQL for nopCommerce
echo "Setting up MySQL for nopCommerce..."

# Find MySQL binary
MYSQL_CMD=""
if [ -f "/usr/bin/mysql" ]; then
    MYSQL_CMD="/usr/bin/mysql"
elif [ -f "/usr/local/bin/mysql" ]; then
    MYSQL_CMD="/usr/local/bin/mysql"
else
    echo "MySQL not found, installing..."
    sudo apt update
    sudo DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
    MYSQL_CMD="/usr/bin/mysql"
fi

# Start MySQL service
sudo systemctl start mysql
sudo systemctl enable mysql

# Set up MySQL user and database
sudo $MYSQL_CMD -e "
CREATE USER IF NOT EXISTS 'nopuser'@'localhost' IDENTIFIED BY 'NopProd2024!@#';
GRANT ALL PRIVILEGES ON *.* TO 'nopuser'@'localhost';
CREATE DATABASE IF NOT EXISTS nopcommerce_prod CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
FLUSH PRIVILEGES;
"

# Test connection
$MYSQL_CMD -u nopuser -p'NopProd2024!@#' -e "SELECT 'MySQL setup successful!' as Status;"

echo "MySQL setup completed!"