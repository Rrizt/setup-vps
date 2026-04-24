#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

# Function to check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root atau dengan sudo"
        print_message "Gunakan: sudo bash $0"
        exit 1
    fi
}

# Function to check OS compatibility
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Tidak dapat mendeteksi OS. Script ini hanya support Ubuntu/Debian"
        exit 1
    fi
    
    if [[ "$OS" != "ubuntu" ]] && [[ "$OS" != "debian" ]]; then
        print_error "OS $OS tidak didukung. Script ini hanya untuk Ubuntu dan Debian"
        exit 1
    fi
    
    print_message "OS terdeteksi: $OS $VER"
}

# Function to update system
update_system() {
    print_header "UPDATE SYSTEM PACKAGES"
    print_message "Mengupdate package list..."
    apt-get update -y
    
    print_message "Mengupgrade packages..."
    apt-get upgrade -y
    
    print_success "System update completed!"
}

# Function to install Node.js 20
install_nodejs() {
    print_header "INSTALLING NODE.JS 20"
    
    # Check if Node.js is already installed
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v)
        print_warning "Node.js sudah terinstall: $NODE_VERSION"
        
        if [[ "$NODE_VERSION" == v20* ]]; then
            print_success "Node.js 20 sudah terinstall!"
            return
        else
            print_message "Menghapus Node.js versi lama..."
            apt-get remove -y nodejs
            apt-get autoremove -y
        fi
    fi
    
    # Install required dependencies
    print_message "Menginstall dependencies..."
    apt-get install -y ca-certificates curl gnupg
    
    # Setup NodeSource repository for Node.js 20
    print_message "Menambahkan repository NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    
    # Install Node.js 20
    print_message "Menginstall Node.js 20..."
    apt-get install -y nodejs
    
    # Verify installation
    if command -v node &> /dev/null; then
        print_success "Node.js $(node -v) berhasil diinstall!"
        print_success "npm $(npm -v) berhasil diinstall!"
    else
        print_error "Gagal menginstall Node.js"
        exit 1
    fi
}

# Function to install npm and update to latest
install_npm() {
    print_header "UPDATING NPM TO LATEST VERSION"
    
    print_message "Mengupdate npm ke versi terbaru..."
    npm install -g npm@latest
    
    print_success "npm $(npm -v) - Updated!"
}

# Function to install PM2
install_pm2() {
    print_header "INSTALLING PM2 PROCESS MANAGER"
    
    # Check if PM2 is already installed
    if command -v pm2 &> /dev/null; then
        PM2_VERSION=$(pm2 -v)
        print_warning "PM2 sudah terinstall: v$PM2_VERSION"
        print_message "Mengupdate PM2 ke versi terbaru..."
        npm install -g pm2@latest
        pm2 update
        print_success "PM2 updated!"
    else
        print_message "Menginstall PM2 secara global..."
        npm install -g pm2
    fi
    
    # Setup PM2 auto-start on boot
    print_message "Mengkonfigurasi PM2 auto-start pada boot..."
    
    # Detect init system
    if command -v systemctl &> /dev/null; then
        print_message "Systemd terdeteksi, mengkonfigurasi PM2 startup..."
        pm2 startup systemd -u root --hp /root
        print_success "PM2 auto-start configured with systemd!"
    elif command -v initctl &> /dev/null; then
        print_message "Upstart terdeteksi, mengkonfigurasi PM2 startup..."
        pm2 startup upstart -u root --hp /root
        print_success "PM2 auto-start configured with upstart!"
    else
        print_warning "Tidak dapat mendeteksi init system, skip auto-start configuration"
        print_message "Jalankan 'pm2 startup' secara manual untuk konfigurasi auto-start"
    fi
    
    # Save PM2 process list (even if empty)
    pm2 save --force
    
    # Install PM2 logrotate module
    print_message "Menginstall PM2 logrotate module..."
    pm2 install pm2-logrotate
    
    # Configure logrotate
    print_message "Mengkonfigurasi PM2 logrotate..."
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:retain 30
    pm2 set pm2-logrotate:compress true
    pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss
    pm2 set pm2-logrotate:workerInterval 30
    pm2 set pm2-logrotate:rotateInterval '0 0 * * *'
    pm2 set pm2-logrotate:rotateModule true
    
    # Verify installation
    if command -v pm2 &> /dev/null; then
        print_success "PM2 v$(pm2 -v) berhasil diinstall dan dikonfigurasi!"
        
        # Show PM2 status
        print_message "Status PM2:"
        pm2 status
    else
        print_error "Gagal menginstall PM2"
        exit 1
    fi
}

# Function to create PM2 ecosystem file template
create_pm2_template() {
    print_header "CREATING PM2 ECOSYSTEM TEMPLATE"
    
    TEMPLATE_DIR="/root/pm2-templates"
    mkdir -p "$TEMPLATE_DIR"
    
    cat > "$TEMPLATE_DIR/ecosystem.config.js" << 'EOF'
// PM2 Ecosystem File Template
// Letakkan file ini di root project Anda dan rename menjadi ecosystem.config.js
// Jalankan dengan: pm2 start ecosystem.config.js

module.exports = {
  apps: [{
    name: 'my-app',                    // Nama aplikasi
    script: 'app.js',                  // File utama aplikasi
    instances: 'max',                  // Jumlah instance (max = semua CPU core)
    exec_mode: 'cluster',              // Mode: cluster atau fork
    watch: false,                      // Auto-restart jika file berubah
    max_memory_restart: '500M',        // Restart jika memory melebihi batas
    
    // Environment variables
    env: {
      NODE_ENV: 'development',
      PORT: 3000
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    
    // Log configuration
    error_file: 'logs/err.log',
    out_file: 'logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    
    // Advanced options
    autorestart: true,
    max_restarts: 10,
    restart_delay: 4000,
    kill_timeout: 5000
  }]
};
EOF

    cat > "$TEMPLATE_DIR/README.md" << 'EOF'
# PM2 Template & Commands

## Basic PM2 Commands:
```bash
pm2 start app.js                    # Start application
pm2 start app.js --name "my-app"    # Start with custom name
pm2 start app.js -i max             # Start with max instances (cluster mode)
pm2 start ecosystem.config.js       # Start with ecosystem file
pm2 list                            # List all processes
pm2 status                          # Show process status
pm2 logs                            # Show logs
pm2 logs --lines 100                # Show last 100 lines
pm2 monit                           # Monitor processes (real-time)
pm2 stop all                        # Stop all processes
pm2 stop my-app                     # Stop specific process
pm2 restart all                     # Restart all processes
pm2 reload all                      # Reload all (0-second downtime)
pm2 delete all                      # Delete all processes
pm2 delete my-app                   # Delete specific process
pm2 save                            # Save current process list
pm2 resurrect                       # Restore previously saved processes
pm2 startup                         # Generate startup script
pm2 unstartup                       # Remove startup script
pm2 update                          # Update PM2
pm2 flush                           # Flush all logs
pm2 reset my-app                    # Reset restart counter
