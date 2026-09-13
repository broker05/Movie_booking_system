#!/usr/bin/env bash
# ==============================================================================
# Movie Booking System - Automated Production Deployment & SSL Script
# ==============================================================================
# Usage:
#   bash scripts/deploy.sh
# ==============================================================================

set -euo pipefail

DOMAIN="${1:-rhrony05.me}"
EMAIL="${2:-muhammadrony147@gmail.com}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}==> [1/4] Pulling latest production code from GitHub...${NC}"
git pull origin main

echo -e "${BLUE}==> [2/4] Checking SSL/TLS Certificates for ${DOMAIN}...${NC}"
if [ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]; then
    echo -e "${YELLOW}SSL certificate not found. Temporarily stopping frontend to free port 80...${NC}"
    docker compose -f docker-compose.prod.yml stop frontend || true
    echo -e "${YELLOW}Requesting fresh certificate from Let's Encrypt...${NC}"
    sudo certbot certonly --standalone \
        -d "${DOMAIN}" -d "www.${DOMAIN}" \
        --non-interactive --agree-tos -m "${EMAIL}"
    sudo mkdir -p /var/www/certbot
    echo -e "${GREEN}SSL Certificate successfully generated and active!${NC}"
else
    echo -e "${GREEN}SSL Certificate already exists and is active.${NC}"
fi

echo -e "${BLUE}==> [3/4] Building and launching production container stack...${NC}"
docker compose -f docker-compose.prod.yml up -d --build

echo -e "${BLUE}==> [4/4] Cleaning up unused dangling Docker images...${NC}"
docker image prune -f

echo ""
echo -e "${GREEN}===================================================================${NC}"
echo -e "${GREEN}🚀 DEPLOYMENT COMPLETE!${NC}"
echo -e "${GREEN}Application is live and secure at: https://${DOMAIN}${NC}"
echo -e "${GREEN}===================================================================${NC}"
