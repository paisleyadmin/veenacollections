#!/bin/bash
ssh -o StrictHostKeyChecking=no ubuntu@129.146.167.43 "
    cd /tmp
    sudo docker-compose -f docker-compose.network-fixed.yml down
    sudo docker rmi nopcommerce:latest 2>/dev/null || true
    sudo docker build -t nopcommerce:latest .
    sudo docker-compose -f docker-compose.network-fixed.yml up -d
    echo Deployment completed - checking status:
    sleep 10
    sudo docker ps
"
