#!/bin/bash

# Kernel source directory and architecture
KERNEL_DIR="/home/chris/work/linux-6.12.1"
KERNEL_ARCH="x86_64"  # Adjust based on your architecture (e.g., x86, ARM)
LOG_FILE="/home/chris/kernel_build_log.txt"
CONFIG_BACKUP_DIR="/home/chris/kernel_config_backup"
HWINFO_FILE="/media/chris/656B4F2157714D36/hwinfo.txt"  # Corrected path to hwinfo.txt file

# Default init path for systemd-based systems
DEFAULT_INIT="/lib/systemd/systemd"
DEFAULT_HOSTNAME="chris"

# Function to check disk space
check_disk_space() {
    required_space=10000  # Required space in MB (10 GB)
    available_space=$(df --output=avail / | tail -n 1)
    if [ "$available_space" -lt "$required_space" ]; then
        echo "Insufficient disk space for kernel build. Please free up space."
        exit 1
    fi
}

# Function to install dependencies if missing
check_and_install_dependencies() {
    echo "Checking for necessary build dependencies..."
    dependencies=("gcc" "make" "libncurses-dev" "bc" "libssl-dev" "flex" "bison")
    missing_deps=()

    # Check if each dependency is installed
    for dep in "${dependencies[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q "ok installed"; then
            missing_deps+=("$dep")
            echo "Error: $dep is not installed. Adding to install list."
        fi
    done

    # If there are missing dependencies, install them automatically
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Missing dependencies: ${missing_deps[*]}"
        sudo apt update
        for dep in "${missing_deps[@]}"; do
            sudo apt install -y "$dep"
        done
        echo "Dependencies installed. Please retry the kernel build."
        exit 0
    else
        echo "All dependencies are installed."
    fi
}

# Function to parse the hardware information from hwinfo.txt
parse_hwinfo() {
    echo "Parsing hardware information from $HWINFO_FILE..."

    # Initialize hardware flags
    HAS_AMD_GPU=0
    HAS_INTEL_GPU=0
    HAS_ETHERNET=0
    HAS_WIRELESS=0
    HAS_SATA=0
    HAS_NVME=0
    CPU_CORES=0
    CPU_MODEL=""

    # Parsing hardware data from hwinfo.txt
    while IFS= read -r line; do
        if [[ "$line" =~ "CPU" ]]; then
            CPU_MODEL=$(echo "$line" | grep -oP 'Intel|AMD|\w+')
            CPU_CORES=$(echo "$line" | grep -oP '\d+(?= cores)')
        fi
        if [[ "$line" =~ "NVIDIA" ]]; then
            HAS_AMD_GPU=1  # Assuming an AMD GPU based on keyword in hwinfo.txt
        fi
        if [[ "$line" =~ "Intel" ]] && [[ "$line" =~ "GPU" ]]; then
            HAS_INTEL_GPU=1  # Intel GPU
        fi
        if [[ "$line" =~ "Ethernet" ]]; then
            HAS_ETHERNET=1  # Ethernet detected
        fi
        if [[ "$line" =~ "Wi-Fi" ]]; then
            HAS_WIRELESS=1  # Wireless detected
        fi
        if [[ "$line" =~ "SATA" ]]; then
            HAS_SATA=1  # SATA storage detected
        fi
        if [[ "$line" =~ "NVMe" ]]; then
            HAS_NVME=1  # NVMe storage detected
        fi
    done < "$HWINFO_FILE"
}

# Function to auto-configure the kernel based on hardware and advanced features
auto_configure_kernel() {
    echo "Auto-configuring the kernel for Dell 2024..."

    # Start with default configuration
    make defconfig

    # Set init system (systemd)
    sed -i 's/^# CONFIG_DEFAULT_INIT is not set/CONFIG_DEFAULT_INIT="'"$DEFAULT_INIT"'"/' .config

    # Set hostname
    sed -i 's/^# CONFIG_DEFAULT_HOSTNAME is not set/CONFIG_DEFAULT_HOSTNAME="'"$DEFAULT_HOSTNAME"'"/' .config

    # Enable maximum features with compatibility
    sed -i 's/^# CONFIG_COMPILE_TEST is not set/CONFIG_COMPILE_TEST=y/' .config  # Compile extra tests
    sed -i 's/^# CONFIG_WERROR is not set/CONFIG_WERROR=y/' .config  # Enable warnings as errors
    sed -i 's/^# CONFIG_KERNEL_ZSTD is not set/CONFIG_KERNEL_ZSTD=y/' .config  # Set ZSTD compression
    sed -i 's/^# CONFIG_KERNEL_GZIP is not set/CONFIG_KERNEL_GZIP=n/' .config  # Disable Gzip compression
    sed -i 's/^# CONFIG_IPV6 is not set/CONFIG_IPV6=y/' .config  # Enable IPv6

    # Enable filesystems commonly used in modern systems
    sed -i 's/^# CONFIG_EXT4_FS is not set/CONFIG_EXT4_FS=y/' .config  # Ext4 filesystem support
    sed -i 's/^# CONFIG_BTRFS_FS is not set/CONFIG_BTRFS_FS=y/' .config  # Btrfs filesystem support
    sed -i 's/^# CONFIG_F2FS_FS is not set/CONFIG_F2FS_FS=y/' .config  # F2FS filesystem support
    sed -i 's/^# CONFIG_XFS_FS is not set/CONFIG_XFS_FS=y/' .config  # XFS filesystem support

    # Enable hardware drivers for common devices (graphics, network, sound, etc.)
    if [ $HAS_AMD_GPU -eq 1 ]; then
        sed -i 's/^# CONFIG_DRM_AMDGPU is not set/CONFIG_DRM_AMDGPU=y/' .config  # Enable AMD GPU driver
    fi

    if [ $HAS_INTEL_GPU -eq 1 ]; then
        sed -i 's/^# CONFIG_DRM_I915 is not set/CONFIG_DRM_I915=y/' .config  # Enable Intel GPU driver
    fi

    if [ $HAS_ETHERNET -eq 1 ]; then
        sed -i 's/^# CONFIG_IGB is not set/CONFIG_IGB=y/' .config  # Enable Intel Ethernet drivers
    fi

    if [ $HAS_WIRELESS -eq 1 ]; then
        sed -i 's/^# CONFIG_MAC80211 is not set/CONFIG_MAC80211=y/' .config  # Enable wireless networking
    fi

    # Enable NVMe if detected
    if [ $HAS_NVME -eq 1 ]; then
        sed -i 's/^# CONFIG_NVME is not set/CONFIG_NVME=y/' .config  # Enable NVMe support
    fi

    # Enable SATA if detected
    if [ $HAS_SATA -eq 1 ]; then
        sed -i 's/^# CONFIG_SATA_AHCI is not set/CONFIG_SATA_AHCI=y/' .config  # Enable SATA support
    fi

    # Enable advanced CPU power management features
    sed -i 's/^# CONFIG_CPU_FREQ is not set/CONFIG_CPU_FREQ=y/' .config 
 sed -i 's/^# CONFIG_CPU_IDLE is not set/CONFIG_CPU_IDLE=y/' .config  # CPU idle management for power savings

    # Enable Vulkan (for modern graphics support)
    sed -i 's/^# CONFIG_DRM_VK is not set/CONFIG_DRM_VK=y/' .config  # Enable Vulkan graphics support

    # Enable advanced audio support (ALSA, HDA, codecs)
    sed -i 's/^# CONFIG_SND_HDA_INTEL is not set/CONFIG_SND_HDA_INTEL=y/' .config  # Enable Intel HD audio
    sed -i 's/^# CONFIG_SND_HDA_CODEC_REALTEK is not set/CONFIG_SND_HDA_CODEC_REALTEK=y/' .config  # Realtek HD audio codecs
    sed -i 's/^# CONFIG_SND_HDA_CODEC_SIGMATEL is not set/CONFIG_SND_HDA_CODEC_SIGMATEL=y/' .config  # Sigmatel codecs
    sed -i 's/^# CONFIG_SND_HDA_CODEC_CONEXANT is not set/CONFIG_SND_HDA_CODEC_CONEXANT=y/' .config  # Conexant codecs (if applicable)

    # Enable Bluetooth implementations (Classic, LE)
    sed -i 's/^# CONFIG_BT is not set/CONFIG_BT=y/' .config  # Enable Bluetooth
    sed -i 's/^# CONFIG_BT_RFCOMM is not set/CONFIG_BT_RFCOMM=y/' .config  # Bluetooth RFCOMM support
    sed -i 's/^# CONFIG_BT_BREDR is not set/CONFIG_BT_BREDR=y/' .config  # Bluetooth BR/EDR support
    sed -i 's/^# CONFIG_BT_LE is not set/CONFIG_BT_LE=y/' .config  # Bluetooth Low Energy (LE) support

    # Enable Wi-Fi support (common chipset drivers)
    sed -i 's/^# CONFIG_MAC80211 is not set/CONFIG_MAC80211=y/' .config  # Enable 802.11 wireless support
    sed -i 's/^# CONFIG_WIRELESS_EXT is not set/CONFIG_WIRELESS_EXT=y/' .config  # Enable wireless extensions

    # Enable advanced security features
    sed -i 's/^# CONFIG_SECURITY_SELINUX is not set/CONFIG_SECURITY_SELINUX=y/' .config  # Enable SELinux (security)
    sed -i 's/^# CONFIG_SECURITY_YAMA is not set/CONFIG_SECURITY_YAMA=y/' .config  # Enable Yama security module

    # Enable support for new kernel features (e.g., Lockdown)
    sed -i 's/^# CONFIG_LOCKDOWN_LSM is not set/CONFIG_LOCKDOWN_LSM=y/' .config  # Enable Lockdown LSM (for kernel lockdown security)

    # Enable Network support (IPv6, etc.)
    sed -i 's/^# CONFIG_IPV6 is not set/CONFIG_IPV6=y/' .config  # Enable IPv6 support
    sed -i 's/^# CONFIG_NETFILTER is not set/CONFIG_NETFILTER=y/' .config  # Enable Netfilter (firewalling)
    sed -i 's/^# CONFIG_NETFILTER_XT_MATCH_IPCOMP is not set/CONFIG_NETFILTER_XT_MATCH_IPCOMP=y/' .config  # Enable IPComp for IPsec

    # Enable support for new CPU architectures (if needed)
    sed -i 's/^# CONFIG_X86_64 is not set/CONFIG_X86_64=y/' .config  # Enable x86_64 architecture (64-bit support)
    sed -i 's/^# CONFIG_X86_GENERIC is not set/CONFIG_X86_GENERIC=y/' .config  # Enable generic x86 settings for 64-bit systems

    # Enable sound support for USB and FireWire (if applicable)
    sed -i 's/^# CONFIG_SND_USB_AUDIO is not set/CONFIG_SND_USB_AUDIO=y/' .config  # Enable USB sound support
    sed -i 's/^# CONFIG_SND_FIREWIRE is not set/CONFIG_SND_FIREWIRE=y/' .config  # Enable FireWire sound support

    # Enable support for advanced filesystems and cryptographic features
    sed -i 's/^# CONFIG_CRYPTO_AES is not set/CONFIG_CRYPTO_AES=y/' .config  # Enable AES encryption support
    sed -i 's/^# CONFIG_CRYPTO_SHA256 is not set/CONFIG_CRYPTO_SHA256=y/' .config  # Enable SHA-256 hash support
    sed -i 's/^# CONFIG_F2FS_FS is not set/CONFIG_F2FS_FS=y/' .config  # Enable F2FS filesystem support (if applicable)
    sed -i 's/^# CONFIG_XFS_FS is not set/CONFIG_XFS_FS=y/' .config  # Enable XFS filesystem support

    # Enable drivers for modern GPU support (e.g., AMD, NVIDIA, Intel)
    sed -i 's/^# CONFIG_DRM_AMDGPU is not set/CONFIG_DRM_AMDGPU=y/' .config  # Enable AMD GPU drivers
    sed -i 's/^# CONFIG_DRM_I915 is not set/CONFIG_DRM_I915=y/' .config  # Enable Intel GPU drivers
    sed -i 's/^# CONFIG_DRM_NOUVEAU is not set/CONFIG_DRM_NOUVEAU=y/' .config  # Enable Nouveau (NVIDIA open-source driver)

    # Enable support for modern storage (NVMe, etc.)
    sed -i 's/^# CONFIG_NVME is not set/CONFIG_NVME=y/' .config  # Enable NVMe support
    sed -i 's/^# CONFIG_BLK_DEV_NVME is not set/CONFIG_BLK_DEV_NVME=y/' .config  # Enable NVMe block devices

    # Enable experimental features (if you want to try them)
    sed -i 's/^# CONFIG_EXPERIMENTAL is not set/CONFIG_EXPERIMENTAL=y/' .config  # Enable experimental features for testing
}

# Function to backup the .config file
backup_config() {
    if [ ! -d "$CONFIG_BACKUP_DIR" ]; then
        mkdir -p "$CONFIG_BACKUP_DIR"
    fi
    cp .config "$CONFIG_BACKUP_DIR/config_$(date +'%Y%m%d_%H%M%S').bak"
}

# Function to build the kernel but NOT install or reboot
build_kernel() {
    echo "Building the kernel..."

    # Compile the kernel with all cores
    make -j$(nproc) || { echo "Kernel build failed!"; exit 1; }

    # Store the kernel and its modules
    echo "Kernel built successfully. Saving kernel image and modules..."
    cp arch/x86/boot/bzImage /boot/vmlinuz-custom
    cp -r lib/modules/$(make kernelversion) /lib/modules/custom/
}

# Main script logic
echo "Starting automated kernel build process for Dell 2024..."

# Check if dependencies are installed
check_and_install_dependencies

# Check disk space availability
check_disk_space

# Navigate to the kernel source directory
cd "$KERNEL_DIR" || { echo "Kernel source directory not found!"; exit 1; }

# Backup the existing configuration before any changes
backup_config

# Parse hardware information
parse_hwinfo

# Auto-configure the kernel based on hardware and advanced features
auto_configure_kernel

# Build the kernel (without installing or rebooting)
build_kernel

echo "Kernel image and modules saved successfully. Please install manually if needed."
