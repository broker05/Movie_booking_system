#!/usr/bin/env bash
# ==============================================================================
# Movie Booking System - Automated Server Provisioning & Hardening Script
# Target OS: Ubuntu 22.04 / 24.04 LTS
# Steps:
#   1. System package update & upgrade
#   2. 2GB Linux Swap Space creation (prevents OOM crashes during Docker builds)
#   3. UFW Firewall configuration (allows ports 22, 80, 443; seals all other ports)
#   4. Official Docker Engine & Docker Compose installation
#   5. User permission assignment for Docker socket
# ==============================================================================

set -euo pipefail

# ANSI color formatting for clear, readable output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Ensure script is run with root/sudo privileges
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run with root privileges. Please run with: sudo bash setup-server.sh"
    exit 1
fi

TARGET_USER="${SUDO_USER:-azureuser}"
log_info "Target non-root user identified as: ${TARGET_USER}"

# ------------------------------------------------------------------------------
# Step 1: Update System Packages
# ------------------------------------------------------------------------------
log_info "Updating package lists and upgrading system packages..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg lsb-release git htop ufw
log_success "Base system packages updated successfully."

# ------------------------------------------------------------------------------
# Step 2: Configure 2GB Swap Space
# ------------------------------------------------------------------------------
log_info "Checking virtual memory / swap configuration..."
if [ -f /swapfile ]; then
    log_warn "Swapfile already exists at /swapfile. Skipping swap creation."
else
    log_info "Creating 2GB swap file to prevent out-of-memory errors..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # Make swap permanent across reboots
    if ! grep -q '/swapfile none swap sw 0 0' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # Set swappiness to 10 (prefers physical RAM, uses swap only when necessary)
    sysctl vm.swappiness=10
    if ! grep -q 'vm.swappiness=10' /etc/sysctl.conf; then
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
    fi
    log_success "2GB Swap successfully configured and enabled."
fi

# ------------------------------------------------------------------------------
# Step 3: Configure UFW (Uncomplicated Firewall)
# ------------------------------------------------------------------------------
log_info "Configuring UFW firewall rules..."
ufw default deny incoming
ufw default allow outgoing

# Allow essential ports
ufw allow 22/tcp comment 'SSH Remote Management'
ufw allow 80/tcp comment 'HTTP Web Traffic'
ufw allow 443/tcp comment 'HTTPS Encrypted Web Traffic'

# Enable firewall non-interactively
ufw --force enable
log_success "UFW Firewall active: ports 22, 80, 443 open. All internal ports (like 5432) blocked."

# ------------------------------------------------------------------------------
# Step 4: Install Official Docker Engine & Docker Compose Plugin
# ------------------------------------------------------------------------------
log_info "Checking Docker installation..."
if command -v docker &> /dev/null; then
    log_warn "Docker is already installed. Skipping installation."
else
    log_info "Setting up Docker official GPG key and repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    log_success "Docker Engine and Docker Compose plugin installed successfully."
fi

# ------------------------------------------------------------------------------
# Step 5: Grant User Docker Permissions
# ------------------------------------------------------------------------------
if id "${TARGET_USER}" &>/dev/null; then
    usermod -aG docker "${TARGET_USER}"
    log_success "User '${TARGET_USER}' added to the 'docker' group."
else
    log_warn "User '${TARGET_USER}' not found. Please add your user to docker group manually."
fi

# ------------------------------------------------------------------------------
# Step 6: Verification & Status Summary
# ------------------------------------------------------------------------------
echo ""
echo "=============================================================================="
log_success "SERVER PROVISIONING COMPLETE!"
echo "=============================================================================="
echo "• Docker Version: $(docker --version)"
echo "• Docker Compose Version: $(docker compose version)"
echo ""
echo "• Memory & Swap Status:"
free -h
echo ""
echo "• Active Firewall Rules:"
ufw status verbose
echo "=============================================================================="
echo -e "${YELLOW}Note: To use Docker without sudo, please log out and log back into your SSH session.${NC}"
echo "=============================================================================="
