#!/bin/bash

# Set the kernel source directory and architecture
KERNEL_DIR="/home/chris/work/linux-6.12.1"
KERNEL_ARCH="x86_64"  # Adjust based on your architecture (e.g., x86, ARM)
LOG_FILE="/home/chris/kernel_build_log.txt"
CONFIG_BACKUP_DIR="/home/chris/kernel_config_backup"
CUSTOM_CONFIG_PATH="$1"  # Optional: pass custom config as argument (e.g., ./build_kernel.sh /path/to/custom/config)

# Function to check disk space
function check_disk_space {
    required_space=10000  # Required space in MB (10 GB)
    available_space=$(df --output=avail / | tail -n 1)
    if [ "$available_space" -lt "$required_space" ]; then
        echo "Insufficient disk space for kernel build. Please free up space."
        exit 1
    fi
}

# Function to check and install missing dependencies
function check_and_install_dependencies {
    echo "Checking for necessary build dependencies..."

    dependencies=("gcc" "make" "libncurses-dev" "bc" "libssl-dev" "flex" "bison")
    missing_deps=()

    # Check if each dependency is installed using dpkg-query (for Debian-based systems)
    for dep in "${dependencies[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q "ok installed"; then
            missing_deps+=("$dep")
            echo "Error: $dep is not installed. Adding to install list."
        fi
    done

    # Install missing dependencies if any
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Missing dependencies: ${missing_deps[*]}"
        read -p "Would you like to automatically install missing dependencies? (y/n): " install_choice
        if [[ "$install_choice" == "y" || "$install_choice" == "Y" ]]; then
            echo "Attempting to install missing dependencies..."
            sudo apt update

            for dep in "${missing_deps[@]}"; do
                sudo apt install -y "$dep"
            done

            echo "Dependencies installed. Please retry the kernel build."
            exit 0  # Exit after installing dependencies, prompt the user to rerun the script
        else
            echo "You chose not to install dependencies. Exiting."
            exit 1
        fi
    else
        echo "All dependencies are installed."
    fi
}

# Function to backup the .config file
function backup_config {
    if [ ! -d "$CONFIG_BACKUP_DIR" ]; then
        mkdir -p "$CONFIG_BACKUP_DIR"
    fi
    cp .config "$CONFIG_BACKUP_DIR/config_$(date +'%Y%m%d_%H%M%S').bak"
}

# Function to restore the .config file from backup
function restore_config {
    echo "Restoring previous configuration..."
    cp "$CONFIG_BACKUP_DIR/config_$(ls -1 $CONFIG_BACKUP_DIR | sort -n | tail -n 1)" .config
}

# Function to enable common features automatically
function enable_common_features {
    echo "Enabling common features..."
    # Enable USB support and Bluetooth support as an example
    sed -i 's/^# CONFIG_USB_SUPPORT is not set/CONFIG_USB_SUPPORT=y/' .config
    sed -i 's/^# CONFIG_BLUETOOTH is not set/CONFIG_BLUETOOTH=y/' .config
    # Add more common features here as needed
}

# Function to check for configuration conflicts
function check_for_conflicts {
    echo "Checking for configuration conflicts..."
    if grep -q "CONFIG_EXT4_FS=y" .config && grep -q "CONFIG_BTRFS_FS=y" .config; then
        echo "WARNING: Both EXT4 and Btrfs enabled. These may not coexist properly."
    fi
    # Add additional checks for conflicts here
}

# Function to log errors
function log_error {
    echo "ERROR: $1"
    echo "$(date) - ERROR: $1" >> "$LOG_FILE"
}

# Function to send failure notification (email)
function send_failure_notification {
    SUBJECT="Kernel Build Failed"
    EMAIL="your_email@example.com"
    BODY="The kernel build process failed. Please check the log at $LOG_FILE."
    echo "$BODY" | mail -s "$SUBJECT" "$EMAIL"
}

# Function to verify that the kernel modules were installed correctly
function verify_modules {
    MODULES_DIR="/lib/modules/$(uname -r)"
    if [ ! -d "$MODULES_DIR" ]; then
        log_error "Kernel modules directory not found. Ensure that kernel modules were installed correctly."
        send_failure_notification
        exit 1
    fi
}

# Check dependencies before starting the build process
check_and_install_dependencies

# Check disk space availability
check_disk_space

# Navigate to the kernel source directory
cd "$KERNEL_DIR" || { echo "Kernel source directory not found!"; exit 1; }

# Backup the existing configuration before any changes
backup_config

# Step 1: Start with the base configuration
if [ ! -f ".config" ]; then
    echo "Starting with default configuration..."
    make defconfig
else
    echo "Configuration file already exists. Skipping defconfig step."
fi

# Step 2: Optionally use a custom configuration if provided
if [ -f "$CUSTOM_CONFIG_PATH" ]; then
    echo "Using custom configuration from $CUSTOM_CONFIG_PATH"
    cp "$CUSTOM_CONFIG_PATH" .config
else
    echo "No custom configuration provided. Using default."
fi

# Step 3: Enable common features automatically
enable_common_features

# Step 4: Check for configuration conflicts
check_for_conflicts

# Step 5: Check and update configuration based on dependencies
echo "Running 'make oldconfig' to update configuration and check dependencies..."
make oldconfig

# Step 6: Check for kernel version and handle modules
KERNEL_VERSION=$(make kernelversion)
KERNEL_INSTALL_DIR="/boot/kernel-$KERNEL_VERSION"

# Step 7: Rebuild only if configuration has changed
if [ "$CONFIG_LAST_MODIFIED" -eq $(stat -c %Y .config) ]; then
    echo "Configuration hasn't changed, skipping rebuild."
else
    echo "Configuration has changed, proceeding with build."
    make -j$(nproc) || { log_error "Kernel build failed!"; send_failure_notification; exit 1; }
fi

# Step 8: Install kernel modules
sudo make modules_install || { log_error "Module installation failed."; send_failure_notification; exit 1; }

# Step 9: Install the kernel
sudo make INSTALL_MOD_PATH=$KERNEL_INSTALL_DIR modules_install || { log_error "Kernel installation failed."; send_failure_notification; exit 1; }
sudo make INSTALL_PATH=$KERNEL_INSTALL_DIR install || { log_error "Kernel installation failed."; send_failure_notification; exit 1; }

# Step 10: Verify module installation
verify_modules

echo "Kernel build and installation completed successfully."

# Final log
echo "$(date) - Kernel build process completed successfully." >> "$LOG_FILE"
