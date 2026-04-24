#!/bin/bash

# ============================================
# Script Auto Setup VPS - Node.js 20, npm, PM2, zip, unzip
# Compatible with Ubuntu/Debian
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root atau dengan sudo"
        print_message "Gunakan: sudo bash $0"
        exit 1
    fi
}

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

update_system() {
    print_header "UPDATE SYSTEM PACKAGES"
    print_message "Mengupdate package list..."
    apt-get update -y
    print_message "Mengupgrade packages..."
    apt-get upgrade -y
    print_success "System update completed!"
}

install_nodejs() {
    print_header "INSTALLING NODE.JS 20"
    
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
    
    print_message "Menginstall dependencies..."
    apt-get install -y ca-certificates curl gnupg
    print_message "Menambahkan repository NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    print_message "Menginstall Node.js 20..."
    apt-get install -y nodejs
    
    if command -v node &> /dev/null; then
        print_success "Node.js $(node -v) berhasil diinstall!"
        print_success "npm $(npm -v) berhasil diinstall!"
    else
        print_error "Gagal menginstall Node.js"
        exit 1
    fi
}

install_npm() {
    print_header "UPDATING NPM TO LATEST VERSION"
    print_message "Mengupdate npm ke versi terbaru..."
    npm install -g npm@latest
    print_success "npm $(npm -v) - Updated!"
}

install_pm2() {
    print_header "INSTALLING PM2 PROCESS MANAGER"
    
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
    
    print_message "Mengkonfigurasi PM2 auto-start pada boot..."
    
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
    
    pm2 save --force
    
    print_message "Menginstall PM2 logrotate module..."
    pm2 install pm2-logrotate
    
    print_message "Mengkonfigurasi PM2 logrotate..."
    pm2 set pm2-logrotate:max_size 10M
    pm2 set pm2-logrotate:retain 30
    pm2 set pm2-logrotate:compress true
    pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss
    pm2 set pm2-logrotate:workerInterval 30
    pm2 set pm2-logrotate:rotateInterval '0 0 * * *'
    pm2 set pm2-logrotate:rotateModule true
    
    if command -v pm2 &> /dev/null; then
        print_success "PM2 v$(pm2 -v) berhasil diinstall dan dikonfigurasi!"
        print_message "Status PM2:"
        pm2 status
    else
        print_error "Gagal menginstall PM2"
        exit 1
    fi
}

create_pm2_template() {
    print_header "CREATING PM2 ECOSYSTEM TEMPLATE"
    
    TEMPLATE_DIR="/root/pm2-templates"
    mkdir -p "$TEMPLATE_DIR"
    
    # Create ecosystem.config.js
    cat > "$TEMPLATE_DIR/ecosystem.config.js" <<'ENDOFFILE'
module.exports = {
  apps: [{
    name: 'my-app',
    script: 'app.js',
    instances: 'max',
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'development',
      PORT: 3000
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: 'logs/err.log',
    out_file: 'logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true,
    autorestart: true,
    max_restarts: 10,
    restart_delay: 4000,
    kill_timeout: 5000
  }]
};
ENDOFFILE

    # Create README.md
    cat > "$TEMPLATE_DIR/README.md" <<'ENDOFFILE'
# PM2 Commands Cheatsheet

## Basic Commands:
pm2 start app.js
pm2 start app.js --name "my-app"
pm2 start app.js -i max
pm2 start ecosystem.config.js
pm2 list
pm2 status
pm2 logs
pm2 logs --lines 100
pm2 monit
pm2 stop all
pm2 stop my-app
pm2 restart all
pm2 reload all
pm2 delete all
pm2 delete my-app
pm2 save
pm2 resurrect
pm2 startup
pm2 unstartup
pm2 update
pm2 flush
pm2 reset my-app

## Environment:
pm2 start ecosystem.config.js --env production
pm2 start ecosystem.config.js --env development

## Log Management:
pm2 logs my-app
pm2 logs --format
pm2 flush
pm2 reloadLogs
ENDOFFILE

    # Create deploy-example.sh
    cat > "$TEMPLATE_DIR/deploy-example.sh" <<'ENDOFFILE'
#!/bin/bash
echo "Starting deployment..."
cd /var/www/my-app
npm install --production
pm2 reload ecosystem.config.js --env production
pm2 save
echo "Deployment completed!"
ENDOFFILE

    chmod +x "$TEMPLATE_DIR/deploy-example.sh"
    
    print_success "PM2 templates dibuat di: $TEMPLATE_DIR"
    print_message "Files: ecosystem.config.js, README.md, deploy-example.sh"
}

install_zip() {
    print_header "INSTALLING ZIP AND UNZIP"
    
    if command -v zip &> /dev/null; then
        print_warning "Zip sudah terinstall!"
    else
        print_message "Menginstall zip..."
        apt-get install -y zip
        print_success "Zip berhasil diinstall!"
    fi
    
    if command -v unzip &> /dev/null; then
        print_warning "Unzip sudah terinstall!"
    else
        print_message "Menginstall unzip..."
        apt-get install -y unzip
        print_success "Unzip berhasil diinstall!"
    fi
}

install_additional_tools() {
    print_header "INSTALLING ADDITIONAL TOOLS"
    
    print_message "Menginstall build tools (gcc, g++, make)..."
    apt-get install -y build-essential
    
    print_message "Menginstall git..."
    apt-get install -y git
    
    print_message "Menginstall curl dan wget..."
    apt-get install -y curl wget
    
    print_message "Menginstall htop (system monitor)..."
    apt-get install -y htop
    
    print_success "Additional tools berhasil diinstall!"
}

create_test_project() {
    print_header "TESTING INSTALLATION"
    
    TEST_DIR="/tmp/nodejs-test-$(date +%s)"
    
    print_message "Membuat test project di $TEST_DIR..."
    mkdir -p "$TEST_DIR/logs"
    cd "$TEST_DIR"
    
    npm init -y > /dev/null 2>&1
    
    print_message "Menginstall Express.js untuk testing..."
    npm install express > /dev/null 2>&1
    
    # Create server.js
    cat > server.js <<'ENDOFFILE'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

app.get('/', (req, res) => {
    res.json({
        message: 'Node.js 20 server is running!',
        version: process.version,
        timestamp: new Date().toISOString()
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});

app.listen(port, () => {
    console.log('Server running on http://localhost:' + port);
    console.log('Node.js version: ' + process.version);
});
ENDOFFILE

    # Create ecosystem.config.js
    cat > ecosystem.config.js <<'ENDOFFILE'
module.exports = {
  apps: [{
    name: 'test-server',
    script: 'server.js',
    instances: 1,
    exec_mode: 'fork',
    watch: false,
    env: {
      NODE_ENV: 'development',
      PORT: 3000
    },
    error_file: 'logs/err.log',
    out_file: 'logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    merge_logs: true
  }]
};
ENDOFFILE

    print_message "Menjalankan test server dengan PM2..."
    pm2 start ecosystem.config.js > /dev/null 2>&1
    sleep 3
    
    print_message "Menguji server..."
    if command -v curl &> /dev/null; then
        curl -s http://localhost:3000/ && echo ""
    fi
    
    print_message "PM2 Status:"
    pm2 status
    
    print_message "Membersihkan test project..."
    pm2 delete test-server > /dev/null 2>&1
    cd /
    rm -rf "$TEST_DIR"
    
    print_success "Testing selesai!"
}

display_summary() {
    print_header "INSTALLATION SUMMARY"
    
    echo -e "${GREEN}✓${NC} Node.js    : $(node -v 2>/dev/null || echo 'Not installed')"
    echo -e "${GREEN}✓${NC} npm         : $(npm -v 2>/dev/null || echo 'Not installed')"
    echo -e "${GREEN}✓${NC} PM2         : v$(pm2 -v 2>/dev/null || echo 'Not installed')"
    echo -e "${GREEN}✓${NC} zip         : $(which zip 2>/dev/null && echo 'installed' || echo 'Not installed')"
    echo -e "${GREEN}✓${NC} unzip       : $(which unzip 2>/dev/null && echo 'installed' || echo 'Not installed')"
    echo -e "${GREEN}✓${NC} git         : $(git --version 2>/dev/null || echo 'Not installed')"
    echo -e "${GREEN}✓${NC} gcc         : $(gcc --version 2>/dev/null | head -n 1 || echo 'Not installed')"
    
    echo ""
    echo -e "${BLUE}PM2 Templates: /root/pm2-templates/${NC}"
    echo ""
    echo -e "${BLUE}Quick Commands:${NC}"
    echo -e "  ${CYAN}pm2 start app.js${NC} - Start application"
    echo -e "  ${CYAN}pm2 list${NC} - List all processes"
    echo -e "  ${CYAN}pm2 monit${NC} - Monitor processes"
    echo -e "  ${CYAN}pm2 logs${NC} - View logs"
    echo -e "  ${CYAN}pm2 save${NC} - Save process list"
    
    echo ""
    echo -e "${YELLOW}============================================${NC}"
    print_success "Instalasi selesai! VPS siap digunakan."
    echo -e "${YELLOW}============================================${NC}"
}

main() {
    clear
    
    print_header "VPS AUTO SETUP SCRIPT"
    echo -e "${GREEN}Tools yang akan diinstall:${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} Node.js 20 (LTS)"
    echo -e "  ${CYAN}2.${NC} npm (latest)"
    echo -e "  ${CYAN}3.${NC} PM2 Process Manager + Auto-start"
    echo -e "  ${CYAN}4.${NC} PM2 Logrotate"
    echo -e "  ${CYAN}5.${NC} PM2 Templates"
    echo -e "  ${CYAN}6.${NC} zip & unzip"
    echo -e "  ${CYAN}7.${NC} Build Essentials"
    echo -e "  ${CYAN}8.${NC} Git & Tools"
    echo ""
    
    check_root
    check_os
    
    echo -e "${YELLOW}============================================${NC}"
    read -p "Lanjutkan instalasi? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Instalasi dibatalkan"
        exit 0
    fi
    
    update_system
    install_nodejs
    install_npm
    install_pm2
    create_pm2_template
    install_zip
    install_additional_tools
    create_test_project
    display_summary
    
    print_header "INSTALLATION COMPLETE"
    print_success "VPS Anda sudah siap!"
    print_message "PM2 templates: /root/pm2-templates/"
    print_warning "Disarankan untuk restart VPS: sudo reboot"
    
    pm2 save --force > /dev/null 2>&1
}

main
