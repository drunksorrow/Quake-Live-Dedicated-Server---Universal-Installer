#!/bin/bash
#
# Quake Live Dedicated Server Universal Installer
# Version: 1.2
# Supports Ubuntu 16.04, 18.04, 20.04, 22.04, 24.04+
# Author: Custom installer based on drunksorrow's work
# Updated: 2025-12-14 - Fixed Steam authentication (requires Steam account with Quake Live)
# 

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOGFILE="/var/log/quake_live_install.log"

# Function to print colored messages
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOGFILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOGFILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOGFILE"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOGFILE"
}

# Function to detect Ubuntu version
detect_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        UBUNTU_VERSION=$VERSION_ID
        print_info "Detected Ubuntu version: $UBUNTU_VERSION"
    else
        print_error "Cannot detect Ubuntu version. /etc/os-release not found."
        exit 1
    fi
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root. Please use 'sudo' or login as root."
        exit 1
    fi
    print_success "Running as root user."
}

# Function to check timezone
check_timezone() {
    CURRENT_TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
    print_info "Current system timezone is: $CURRENT_TZ"
    
    read -p "Do you want to change the timezone? (y/n): " change_tz
    if [[ "$change_tz" =~ ^[Yy]$ ]]; then
        read -p "This script is optimized for 'Europe/Bucharest'. Set to Bucharest? (y/n): " use_bucharest
        if [[ "$use_bucharest" =~ ^[Yy]$ ]]; then
            if timedatectl set-timezone "Europe/Bucharest" 2>/dev/null; then
                print_success "Timezone set to Europe/Bucharest"
            else
                print_error "Failed to set timezone. You can set it manually later."
            fi
        else
            print_info "Available timezones can be listed with: timedatectl list-timezones"
            read -p "Enter your desired timezone (e.g., America/New_York): " custom_tz
            if timedatectl set-timezone "$custom_tz" 2>/dev/null; then
                print_success "Timezone set to $custom_tz"
            else
                print_error "Invalid timezone: $custom_tz"
                read -p "Do you want to try again? (y/n): " retry
                if [[ "$retry" =~ ^[Yy]$ ]]; then
                    check_timezone
                else
                    print_warning "Skipping timezone configuration. You can set it later manually."
                fi
            fi
        fi
    else
        print_info "Keeping current timezone: $CURRENT_TZ"
    fi
}

# Function to get password
get_password() {
    while true; do
        read -p "Enter password for 'qlserver' user (visible on screen): " QL_PASSWORD
        if [ -z "$QL_PASSWORD" ]; then
            print_error "Password cannot be empty. Please try again."
        else
            print_success "Password captured. Will use for both qlserver and Samba."
            break
        fi
    done
}

# Function to handle SSH keys
setup_ssh_keys() {
    ROOT_SSH_KEY=""
    
    if [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
        ROOT_SSH_KEY=$(cat /root/.ssh/authorized_keys)
        print_success "Found existing SSH key in root account."
    else
        print_warning "No SSH key found in root's authorized_keys file."
        read -p "Do you want to add an SSH key now for both root and qlserver? (y/n): " add_key
        
        if [[ "$add_key" =~ ^[Yy]$ ]]; then
            print_info "Please paste your SSH public key and press Enter:"
            read ROOT_SSH_KEY
            
            if [ -n "$ROOT_SSH_KEY" ]; then
                mkdir -p /root/.ssh
                chmod 700 /root/.ssh
                echo "$ROOT_SSH_KEY" > /root/.ssh/authorized_keys
                chmod 600 /root/.ssh/authorized_keys
                print_success "SSH key added to root account."
            else
                print_warning "No key provided. Skipping SSH key setup."
            fi
        else
            print_info "Skipping SSH key setup. You can add keys manually later."
        fi
    fi
    
    # Setup SSH for qlserver (will be called after user creation)
    SSH_KEY_TO_COPY="$ROOT_SSH_KEY"
}

# Function to install packages based on Ubuntu version
install_packages() {
    local version=$1
    print_info "Installing packages for Ubuntu $version..."
    
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    
    case $version in
        16.04|18.04|20.04)
            print_info "Installing packages for older Ubuntu versions..."
            apt-get -y install apache2 python3 python-setuptools lib32gcc1 curl nano \
                samba build-essential python-dev python3-dev unzip dos2unix mailutils \
                wget lib32z1 lib32stdc++6 libc6 redis-server git
            ;;
        22.04|24.04)
            print_info "Installing packages for newer Ubuntu versions..."
            apt-get -y install apache2 python3 python3-setuptools curl nano samba \
                build-essential python3-dev unzip dos2unix mailutils wget lib32z1 \
                lib32stdc++6 libc6 lib32gcc-s1 python3-pip g++-12 libbsd-dev \
                libunwind-dev python3-venv redis-server git dos2unix
            ;;
        *)
            if (( $(echo "$version >= 24.04" | bc -l) )); then
                print_warning "Ubuntu $version is newer than tested versions."
                read -p "Attempt installation using Ubuntu 24.04 steps? (y/n): " proceed
                if [[ "$proceed" =~ ^[Yy]$ ]]; then
                    install_packages "24.04"
                    return
                else
                    print_error "Installation cancelled by user."
                    exit 1
                fi
            elif (( $(echo "$version < 16.04" | bc -l) )); then
                print_warning "Ubuntu $version is older than tested versions."
                read -p "Attempt installation using Ubuntu 16.04 steps? (y/n): " proceed
                if [[ "$proceed" =~ ^[Yy]$ ]]; then
                    install_packages "16.04"
                    return
                else
                    print_error "Installation cancelled by user."
                    exit 1
                fi
            fi
            ;;
    esac
    
    print_success "Packages installed successfully."
    
    # Check and install screen separately (optional, non-critical)
    if command -v screen &> /dev/null; then
        print_success "Screen is already installed."
    else
        print_info "Screen not found. Attempting to install screen (optional)..."
        if apt-get -y install screen 2>/dev/null; then
            print_success "Screen installed successfully."
        else
            print_warning "Could not install screen. This is optional and won't affect server operation."
            print_info "Screen is useful for managing server sessions but not required."
        fi
    fi
}

# Function to install ZeroMQ
install_zeromq() {
    local version=$1
    print_info "Installing ZeroMQ library..."
    
    case $version in
        16.04|18.04|20.04)
            # Old method for older Ubuntu - use ZeroMQ 4.3.2 (compatible and available)
            cd /tmp
            
            ZMQ_VERSION="4.3.2"
            ZMQ_URL="https://github.com/zeromq/libzmq/releases/download/v${ZMQ_VERSION}/zeromq-${ZMQ_VERSION}.tar.gz"
            
            print_info "Downloading ZeroMQ ${ZMQ_VERSION} from GitHub..."
            if wget "$ZMQ_URL"; then
                tar -xvzf zeromq-${ZMQ_VERSION}.tar.gz
                rm zeromq-${ZMQ_VERSION}.tar.gz
                cd zeromq-${ZMQ_VERSION}
                
                # Configure and build
                ./configure --without-libsodium
                make
                make install
                ldconfig
                
                cd ..
                rm -rf zeromq-${ZMQ_VERSION}
                
                print_success "ZeroMQ ${ZMQ_VERSION} installed successfully."
            else
                print_error "Failed to download ZeroMQ from GitHub."
                print_info "Attempting to install from Ubuntu repositories as fallback..."
                apt-get -y install libzmq3-dev || apt-get -y install libzmq5-dev
            fi
            
            # Install pip first
            print_info "Installing pip..."
            apt-get -y install python-pip python3-pip 2>/dev/null || apt-get -y install python3-pip
            
            # Install pyzmq - try multiple methods
            print_info "Installing pyzmq..."
            if pip3 install pyzmq 2>/dev/null; then
                print_success "pyzmq installed via pip3"
            elif pip install pyzmq 2>/dev/null; then
                print_success "pyzmq installed via pip"
            elif apt-get -y install python3-zmq; then
                print_success "pyzmq installed via apt (python3-zmq)"
            else
                print_error "Failed to install pyzmq. Trying to continue anyway..."
            fi
            ;;
        22.04|24.04|*)
            # New method for newer Ubuntu
            cd /tmp
            ZMQ_URL="https://github.com/zeromq/libzmq/releases/download/v4.3.5/zeromq-4.3.5.tar.gz"
            wget "$ZMQ_URL"
            tar -xvzf zeromq-4.3.5.tar.gz
            rm zeromq-4.3.5.tar.gz
            cd zeromq-4.3.5
            
            # Disable -Werror for newer compilers
            sed -i 's/-Werror//g' Makefile.am 2>/dev/null || true
            sed -i 's/-Werror//g' Makefile.in 2>/dev/null || true
            
            export CXX=g++-12
            ./configure --without-libsodium
            make
            make install
            ldconfig
            cd ..
            rm -rf zeromq-4.3.5
            
            # Install pyzmq - use apt package for Ubuntu 24.04+
            if command -v python3 -m pip &> /dev/null; then
                python3 -m pip install --break-system-packages pyzmq 2>/dev/null || \
                apt-get -y install python3-zmq
            else
                apt-get -y install python3-zmq
            fi
            ;;
    esac
    
    print_success "ZeroMQ installed successfully."
}

# Function to create qlserver user
create_qlserver_user() {
    print_info "Creating 'qlserver' user..."
    
    useradd -m qlserver
    usermod -a -G sudo qlserver
    chsh -s /bin/bash qlserver
    
    # Set password
    echo "qlserver:$QL_PASSWORD" | chpasswd
    
    # Add to sudoers with NOPASSWD
    echo "qlserver ALL = NOPASSWD: ALL" >> /etc/sudoers
    
    print_success "User 'qlserver' created successfully."
}

# Function to configure Samba
configure_samba() {
    local version=$1
    print_info "Configuring Samba..."
    
    # Stop Samba service
    case $version in
        16.04|18.04)
            /etc/init.d/samba stop 2>/dev/null || systemctl stop smbd 2>/dev/null || true
            ;;
        *)
            systemctl stop smbd 2>/dev/null || true
            ;;
    esac
    
    # Add home directory sharing
    if ! grep -q "\[homes\]" /etc/samba/smb.conf; then
        echo -e "\n[homes]\n    comment = Home Directories\n    browseable = yes\n    read only = no\n    writeable = yes\n    create mask = 0755\n    directory mask = 0755" >> /etc/samba/smb.conf
    fi
    
    # Add www directory sharing
    if ! grep -q "\[www\]" /etc/samba/smb.conf; then
        echo -e "\n[www]\n    comment = WWW Directory\n    path = /var/www\n    browseable = yes\n    read only = no\n    writeable = yes\n    create mask = 0755\n    directory mask = 0755" >> /etc/samba/smb.conf
    fi
    
    # Set Samba password
    (echo "$QL_PASSWORD"; echo "$QL_PASSWORD") | smbpasswd -a qlserver -s
    
    # Start Samba service
    case $version in
        16.04|18.18)
            /etc/init.d/samba start 2>/dev/null || systemctl start smbd 2>/dev/null || true
            ;;
        *)
            systemctl start smbd 2>/dev/null || true
            ;;
    esac
    
    print_success "Samba configured successfully."
}

# Function to setup SSH for qlserver
setup_qlserver_ssh() {
    print_info "Setting up SSH for qlserver user..."
    
    su - qlserver -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    
    if [ -n "$SSH_KEY_TO_COPY" ]; then
        su - qlserver -c "echo '$SSH_KEY_TO_COPY' > ~/.ssh/authorized_keys"
        print_success "SSH key copied to qlserver account."
    else
        print_info "Created empty authorized_keys file for qlserver."
        print_info "You can add SSH keys later using an editor like midnight commander (mc)."
    fi
}

# Function to cleanup partial installation
cleanup_partial_installation() {
    print_warning "Performing cleanup of partial installation..."
    
    # Stop any running processes
    pkill -u qlserver 2>/dev/null || true
    sleep 2
    
    # Remove qlserver user and home
    if id "qlserver" &>/dev/null; then
        print_info "Removing qlserver user..."
        userdel -r qlserver 2>/dev/null || true
        rm -rf /home/qlserver 2>/dev/null || true
    fi
    
    # Remove Samba user
    smbpasswd -x qlserver 2>/dev/null || true
    
    # Remove sudoers entry
    if grep -q "qlserver ALL = NOPASSWD: ALL" /etc/sudoers; then
        sed -i '/qlserver ALL = NOPASSWD: ALL/d' /etc/sudoers
    fi
    
    # Clean Samba config
    if [ -f /etc/samba/smb.conf ]; then
        cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
        sed -i '/^\[homes\]/,/^directory mask = 0755$/d' /etc/samba/smb.conf 2>/dev/null || true
        sed -i '/^\[www\]/,/^directory mask = 0755$/d' /etc/samba/smb.conf 2>/dev/null || true
        systemctl restart smbd 2>/dev/null || /etc/init.d/samba restart 2>/dev/null || true
    fi
    
    print_success "Cleanup completed. You can run the installer again anytime."
}

# Function to install SteamCMD and Quake Live
install_quake_server() {
    print_info "Installing SteamCMD and Quake Live Dedicated Server..."
    echo ""
    
    # Main authentication loop
    while true; do
        print_warning "IMPORTANT: You must own Quake Live on your Steam account to download the server files."
        print_info "Steam no longer allows anonymous downloads for Quake Live."
        echo ""
        echo "Authentication options:"
        echo "  1. Enter Steam password (visible on screen)"
        echo "  2. Enter Steam password (hidden with asterisks)"
        echo "  3. Cancel installation and cleanup"
        echo ""
        
        read -p "Choose option (1/2/3): " steam_option
        
        case $steam_option in
            1|2)
                # Get Steam username (always visible)
                read -p "Enter your Steam username: " STEAM_USER
                
                if [ -z "$STEAM_USER" ]; then
                    print_error "Username cannot be empty."
                    continue
                fi
                
                # Get password based on option
                if [ "$steam_option" = "1" ]; then
                    # Visible password
                    read -p "Enter your Steam password (visible): " STEAM_PASS
                else
                    # Hidden password with asterisks simulation
                    echo -n "Enter your Steam password (hidden): "
                    STEAM_PASS=""
                    while IFS= read -r -s -n1 char; do
                        if [[ $char == $'\0' ]]; then
                            break
                        elif [[ $char == $'\177' ]] || [[ $char == $'\b' ]]; then
                            # Backspace
                            if [ ${#STEAM_PASS} -gt 0 ]; then
                                STEAM_PASS="${STEAM_PASS%?}"
                                echo -ne "\b \b"
                            fi
                        else
                            STEAM_PASS+="$char"
                            echo -n "*"
                        fi
                    done
                    echo ""
                fi
                
                if [ -z "$STEAM_PASS" ]; then
                    print_error "Password cannot be empty."
                    continue
                fi
                
                # Attempt Steam authentication and download
                print_info "Attempting to authenticate with Steam and download Quake Live..."
                print_info "If you have Steam Guard Mobile Auth, approve the login on your phone."
                
                # Create temporary script for su command
                cat > /tmp/steam_install.sh << EOSTEAM
#!/bin/bash
mkdir -p ~/steamcmd
cd ~/steamcmd

# Download SteamCMD if not exists
if [ ! -f steamcmd.sh ]; then
    wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
    tar -xvzf steamcmd_linux.tar.gz
    rm steamcmd_linux.tar.gz
fi

# First run to update SteamCMD itself
./steamcmd.sh +quit

# Now install Quake Live - IMPORTANT: force_install_dir MUST come BEFORE login!
./steamcmd.sh +force_install_dir /home/qlserver/steamcmd/steamapps/common/qlds/ +login "$STEAM_USER" "$STEAM_PASS" +app_update 349090 validate +quit
exit \$?
EOSTEAM
                
                chmod +x /tmp/steam_install.sh
                
                # Run as qlserver user
                if su - qlserver -c "/tmp/steam_install.sh"; then
                    rm -f /tmp/steam_install.sh
                    
                    # Verify installation
                    if [ -f /home/qlserver/steamcmd/steamapps/common/qlds/run_server_x64.sh ]; then
                        print_success "Quake Live Dedicated Server installed successfully!"
                        return 0
                    else
                        print_error "Server files not found after installation."
                        print_info "This usually means authentication failed or you don't own Quake Live."
                    fi
                else
                    rm -f /tmp/steam_install.sh
                    print_error "SteamCMD authentication or download failed."
                    print_info "Common reasons:"
                    echo "  • Incorrect username or password"
                    echo "  • You don't own Quake Live on this Steam account"
                    echo "  • Steam Guard approval was not completed (if using Mobile Auth)"
                    echo "  • Network connection issues"
                fi
                
                # Ask if user wants to retry
                echo ""
                read -p "Do you want to try again with different credentials? (y/n): " retry
                
                if [[ ! "$retry" =~ ^[Yy]$ ]]; then
                    echo ""
                    read -p "Are you sure you want to cancel? Type 'yes' to confirm: " confirm_cancel
                    
                    if [ "$confirm_cancel" = "yes" ]; then
                        print_warning "Installation cancelled by user."
                        cleanup_partial_installation
                        exit 1
                    else
                        print_info "Returning to authentication options..."
                        continue
                    fi
                fi
                ;;
                
            3)
                # Cancel installation
                echo ""
                print_warning "This will remove all files installed so far and exit the installer."
                read -p "Are you sure? Type 'yes' to confirm: " confirm_abort
                
                if [ "$confirm_abort" = "yes" ]; then
                    cleanup_partial_installation
                    print_info "Installation cancelled. You can run this installer again anytime."
                    exit 1
                else
                    print_info "Continuing with installation..."
                    continue
                fi
                ;;
                
            *)
                print_error "Invalid option. Please choose 1, 2, or 3."
                continue
                ;;
        esac
    done
}

# Function to install minqlx
install_minqlx() {
    local version=$1
    print_info "Installing minqlx..."
    
    cd /home/qlserver/steamcmd/steamapps/common/qlds
    
    # Clone and compile minqlx
    git clone https://github.com/MinoMino/minqlx.git
    cd minqlx
    make
    
    # Copy files
    cp -r bin/* /home/qlserver/steamcmd/steamapps/common/qlds/
    cd /home/qlserver/steamcmd/steamapps/common/qlds
    
    # Clone plugins
    git clone https://github.com/MinoMino/minqlx-plugins.git
    
    # Install Python dependencies
    case $version in
        16.04|18.04|20.04)
            apt-get -y install python3-pip
            python3 -m pip install -r minqlx-plugins/requirements.txt
            ;;
        22.04|24.04|*)
            # For Ubuntu 22.04+ - handle different pip versions
            apt-get -y install python3-pip
            
            # Check if pip supports --break-system-packages
            if python3 -m pip install --help 2>&1 | grep -q "break-system-packages"; then
                print_info "Using pip with --break-system-packages flag..."
                export PIP_BREAK_SYSTEM_PACKAGES=1
                
                # Upgrade pip
                python3 -m pip install --break-system-packages --upgrade pip 2>/dev/null || true
                
                # Install requirements
                if python3 -m pip install --break-system-packages -r minqlx-plugins/requirements.txt; then
                    print_success "Python dependencies installed successfully."
                else
                    print_warning "pip installation failed, trying system packages..."
                    apt-get -y install python3-redis python3-requests
                fi
            else
                print_info "Older pip version detected, installing without --break-system-packages..."
                # Try regular pip install first
                if python3 -m pip install -r minqlx-plugins/requirements.txt 2>/dev/null; then
                    print_success "Python dependencies installed successfully."
                else
                    print_warning "pip installation failed, using system packages..."
                    apt-get -y install python3-redis python3-requests
                    if [ $? -eq 0 ]; then
                        print_success "Python dependencies installed via apt."
                    else
                        print_error "Failed to install Python dependencies."
                        print_info "You can manually install them later with:"
                        print_info "  sudo apt-get install python3-redis python3-requests"
                    fi
                fi
            fi
            ;;
    esac
    
    # Fix permissions
    chown -R qlserver:qlserver /home/qlserver/steamcmd
    
    print_success "minqlx installed successfully."
}

# Function to create supervisor installation script
create_supervisor_script() {
    print_info "Creating supervisor installation script..."
    
    cat > /root/install-supervisor.sh << 'EOSCRIPT'
#!/bin/bash

# Supervisor Installation Script for Quake Live Server

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root."
    exit 1
fi

print_info "Installing Supervisor..."
apt-get update
apt-get -y install supervisor

print_info "Configuring Supervisor for Quake Live..."

cat > /etc/supervisor/conf.d/quakelive.conf << 'EOCONF'
[program:quakelive]
command=/home/qlserver/steamcmd/steamapps/common/qlds/run_server_x64_minqlx.sh
user=qlserver
process_name=qzeroded
autostart=true
autorestart=true
stderr_logfile=/var/log/quake.err.log
stdout_logfile=/var/log/quake.out.log
EOCONF

print_success "Supervisor configuration created."

print_info "Restarting Supervisor service..."
service supervisor restart

print_info "Reloading Supervisor configuration..."
supervisorctl reread
supervisorctl update

print_success "Supervisor installed and configured successfully!"
print_info "Your Quake Live server will now start automatically on boot."

echo ""
echo "======================================================================"
print_info "Daily Automatic Reboot Setup (Optional)"
echo "======================================================================"
echo ""

read -p "Do you want to set up a daily automatic reboot? (y/n): " setup_cron

if [[ "$setup_cron" =~ ^[Yy]$ ]]; then
    echo ""
    print_info "Daily server reboots help maintain server stability and apply updates."
    print_info "The recommended time is 6:40 AM (based on low player activity)."
    echo ""
    read -p "Use recommended time (6:40 AM)? (y/n): " use_recommended
    
    if [[ "$use_recommended" =~ ^[Yy]$ ]]; then
        CRON_TIME="40 6"
        print_info "Using recommended time: 6:40 AM"
    else
        while true; do
            echo ""
            print_info "Please enter your preferred reboot time."
            print_info "Format: HH MM (24-hour format)"
            print_info "Example: 03 30 (for 3:30 AM) or 14 15 (for 2:15 PM)"
            echo ""
            read -p "Enter hour (00-23): " hour
            read -p "Enter minute (00-59): " minute
            
            # Validate input
            if [[ "$hour" =~ ^[0-9]+$ ]] && [[ "$minute" =~ ^[0-9]+$ ]] && \
               [ "$hour" -ge 0 ] && [ "$hour" -le 23 ] && \
               [ "$minute" -ge 0 ] && [ "$minute" -le 59 ]; then
                CRON_TIME="$minute $hour"
                print_success "Daily reboot will be set for $(printf '%02d:%02d' $hour $minute)"
                break
            else
                print_error "Invalid time format. Please try again."
                read -p "Try again? (y/n - selecting 'n' will skip crontab setup): " retry
                if [[ ! "$retry" =~ ^[Yy]$ ]]; then
                    print_warning "Skipping crontab setup."
                    print_info "You can set it up manually later with: sudo crontab -e"
                    CRON_TIME=""
                    break
                fi
            fi
        done
    fi
    
    if [ -n "$CRON_TIME" ]; then
        # Remove any existing shutdown cron jobs
        crontab -l 2>/dev/null | grep -v "/sbin/shutdown -r" | crontab - 2>/dev/null || true
        
        # Add new cron job
        (crontab -l 2>/dev/null; echo "$CRON_TIME * * * /sbin/shutdown -r now") | crontab -
        
        print_success "Daily automatic reboot configured successfully!"
        print_info "The server will reboot every day at the specified time."
        
        # Verify crontab
        echo ""
        print_info "Current crontab entries:"
        crontab -l 2>/dev/null | grep shutdown
    fi
else
    print_info "Skipping daily reboot setup."
    print_info "You can configure it later with: sudo crontab -e"
    print_info "Add this line: 40 6 * * * /sbin/shutdown -r now"
fi

echo ""
echo "======================================================================"
print_success "Supervisor installation completed!"
echo "======================================================================"
echo ""

read -p "System restart is recommended to ensure everything starts correctly. Reboot now? (y/n): " reboot_now
if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
    print_info "Rebooting system in 5 seconds..."
    print_warning "Press Ctrl+C to cancel..."
    sleep 5
    reboot
else
    print_info "Please remember to reboot your system later."
    print_info "You can reboot manually with: sudo reboot"
fi
EOSCRIPT
    
    chmod +x /root/install-supervisor.sh
    print_success "Supervisor installation script created at: /root/install-supervisor.sh"
}

# Function to create cleanup script
create_cleanup_script() {
    print_info "Creating cleanup script..."
    
    cat > /root/cleanup-quake-install.sh << 'EOCLEANUP'
#!/bin/bash

# Cleanup script for failed Quake Live installation

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[CLEANUP]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root."
    print_info "Please run: sudo $0"
    exit 1
fi

clear
echo "======================================================================"
echo "          Quake Live Server - Installation Cleanup Script           "
echo "======================================================================"
echo ""
print_warning "This will remove ALL Quake Live server installations and configurations!"
print_warning "This includes:"
echo "  - qlserver user and home directory"
echo "  - All server files and configurations"
echo "  - Samba shares configuration"
echo "  - Cron jobs (daily reboot)"
echo "  - Supervisor configuration"
echo "  - Python virtual environment"
echo ""
read -p "Are you absolutely sure you want to continue? Type 'yes' to confirm: " confirm

if [ "$confirm" != "yes" ]; then
    print_info "Cleanup cancelled. Nothing was changed."
    exit 0
fi

echo ""
print_info "Starting cleanup process..."
echo ""

# Stop Quake Live server if running
if command -v supervisorctl &> /dev/null; then
    print_info "Stopping Quake Live server..."
    supervisorctl stop quakelive 2>/dev/null || true
    print_success "Server stopped."
fi

# Remove qlserver user and home directory
if id "qlserver" &>/dev/null; then
    print_info "Removing qlserver user and home directory..."
    # Kill any processes running as qlserver
    pkill -u qlserver 2>/dev/null || true
    sleep 2
    # Remove user and home directory
    userdel -r qlserver 2>/dev/null || true
    # Force remove home directory if it still exists
    rm -rf /home/qlserver 2>/dev/null || true
    print_success "User 'qlserver' removed."
else
    print_info "User 'qlserver' not found. Skipping."
fi

# Remove Samba user
print_info "Removing Samba user 'qlserver'..."
smbpasswd -x qlserver 2>/dev/null || true
print_success "Samba user removed."

# Remove sudoers entry
print_info "Cleaning sudoers file..."
if grep -q "qlserver ALL = NOPASSWD: ALL" /etc/sudoers; then
    sed -i '/qlserver ALL = NOPASSWD: ALL/d' /etc/sudoers
    print_success "Sudoers entry removed."
else
    print_info "No sudoers entry found. Skipping."
fi

# Remove Samba configurations
print_info "Cleaning Samba configurations..."
if [ -f /etc/samba/smb.conf ]; then
    # Create backup
    cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Remove [homes] section
    sed -i '/^\[homes\]/,/^directory mask = 0755$/d' /etc/samba/smb.conf 2>/dev/null || true
    
    # Remove [www] section
    sed -i '/^\[www\]/,/^directory mask = 0755$/d' /etc/samba/smb.conf 2>/dev/null || true
    
    # Restart Samba
    systemctl restart smbd 2>/dev/null || /etc/init.d/samba restart 2>/dev/null || true
    print_success "Samba configurations cleaned."
else
    print_info "Samba configuration file not found. Skipping."
fi

# Remove cron job for daily reboot
print_info "Removing daily reboot cron job..."
crontab -l 2>/dev/null | grep -v "/sbin/shutdown -r" | crontab - 2>/dev/null || true
print_success "Cron job removed."

# Remove supervisor configuration
if [ -f /etc/supervisor/conf.d/quakelive.conf ]; then
    print_info "Removing Supervisor configuration..."
    rm -f /etc/supervisor/conf.d/quakelive.conf
    if command -v supervisorctl &> /dev/null; then
        supervisorctl reread 2>/dev/null || true
        supervisorctl update 2>/dev/null || true
    fi
    print_success "Supervisor configuration removed."
else
    print_info "Supervisor configuration not found. Skipping."
fi

# Remove Python virtual environment
if [ -d /opt/qlserver-venv ]; then
    print_info "Removing Python virtual environment..."
    rm -rf /opt/qlserver-venv
    print_success "Virtual environment removed."
else
    print_info "Python virtual environment not found. Skipping."
fi

# Remove installation log
if [ -f /var/log/quake_live_install.log ]; then
    print_info "Removing installation log..."
    rm -f /var/log/quake_live_install.log
    print_success "Installation log removed."
fi

# Remove Quake Live logs
if [ -f /var/log/quake.err.log ] || [ -f /var/log/quake.out.log ]; then
    print_info "Removing Quake Live logs..."
    rm -f /var/log/quake.err.log
    rm -f /var/log/quake.out.log
    print_success "Quake Live logs removed."
fi

# Remove ZeroMQ library (optional - may be used by other applications)
print_warning "ZeroMQ library is NOT removed (may be used by other applications)."
print_info "If you want to remove it manually, run: ldconfig -p | grep zmq"

echo ""
echo "======================================================================"
print_success "Cleanup completed successfully!"
echo "======================================================================"
echo ""
print_info "What was removed:"
echo "  ✓ qlserver user and home directory"
echo "  ✓ All server files and configurations"
echo "  ✓ Samba configurations (backup created)"
echo "  ✓ Sudoers entry"
echo "  ✓ Cron jobs"
echo "  ✓ Supervisor configuration"
echo "  ✓ Python virtual environment"
echo "  ✓ Installation logs"
echo ""
print_warning "What was NOT removed:"
echo "  • System packages (apache2, python3, redis, samba, etc.)"
echo "  • ZeroMQ library"
echo "  • Installation scripts in /root"
echo ""
print_info "To remove unused system packages, run:"
echo "  apt-get autoremove"
echo ""
print_info "You can now run the installation script again:"
echo "  /root/install_quake_live.sh"
echo ""
print_success "Your system is clean and ready for a fresh installation!"
echo "======================================================================"
EOCLEANUP
    
    chmod +x /root/cleanup-quake-install.sh
    print_success "Cleanup script created at: /root/cleanup-quake-install.sh"
}

# Main installation function
main() {
    clear
    echo "======================================================================"
    echo "          Quake Live Dedicated Server - Universal Installer          "
    echo "======================================================================"
    echo ""
    
    # Initialize log file
    echo "Installation started at $(date)" > "$LOGFILE"
    
    # Check if running as root
    check_root
    
    # Detect Ubuntu version
    detect_ubuntu_version
    
    # Check timezone
    check_timezone
    
    # Get password
    get_password
    
    # Setup SSH keys
    setup_ssh_keys
    
    # Create cleanup script first (in case something fails)
    create_cleanup_script
    
    # Install packages
    install_packages "$UBUNTU_VERSION"
    
    # Install ZeroMQ
    install_zeromq "$UBUNTU_VERSION"
    
    # Create qlserver user
    create_qlserver_user
    
    # Configure Samba
    configure_samba "$UBUNTU_VERSION"
    
    # Setup SSH for qlserver
    setup_qlserver_ssh
    
    # Install SteamCMD and Quake Live
    install_quake_server
    
    # Install minqlx
    install_minqlx "$UBUNTU_VERSION"
    
    # Create supervisor installation script
    create_supervisor_script
    
    echo ""
    echo "======================================================================"
    print_success "Quake Live Server installation completed successfully!"
    echo "======================================================================"
    echo ""
    print_info "Next steps:"
    echo ""
    echo "  1. Upload your server configuration files using WinSCP/SFTP:"
    echo "     Location: /home/qlserver/steamcmd/steamapps/common/qlds/baseq3/"
    echo "     Files: server.cfg, access.txt, mappool.txt, workshop.txt"
    echo ""
    echo "  2. Upload your minqlx plugins:"
    echo "     Location: /home/qlserver/steamcmd/steamapps/common/qlds/minqlx-plugins/"
    echo "     Example plugins: branding.py, funnysounds.py, listmaps.py"
    echo ""
    echo "  3. Test your server manually:"
    echo "     su - qlserver"
    echo "     screen -S quake  (optional, but recommended)"
    echo "     cd ~/steamcmd/steamapps/common/qlds"
    echo "     ./run_server_x64_minqlx.sh"
    echo ""
    echo "     Watch for:"
    echo "     - Workshop maps downloading automatically"
    echo "     - Minqlx plugins loading without errors"
    echo "     - Server starting successfully"
    echo ""
    echo "  4. After successful testing, install Supervisor (run as root):"
    echo "     exit  (to return to root from qlserver user)"
    echo "     /root/install-supervisor.sh"
    echo ""
    print_info "Additional scripts created:"
    echo "  - /root/install-supervisor.sh  (Run after server testing)"
    echo "  - /root/cleanup-quake-install.sh  (Use if you need to start over)"
    echo ""
    print_warning "Important reminders:"
    echo "  • Configure your firewall separately (UDP/TCP 27960)"
    echo "  • Test the server manually before installing Supervisor"
    echo "  • Workshop maps download automatically from workshop.txt"
    echo ""
    echo "Installation log saved to: $LOGFILE"
    echo "======================================================================"
}

# Run main function
main
