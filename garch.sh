#!/bin/bash 

# + Variables
argc=$#
args=($@)

base_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
errlog="$base_dir/.errlog"
outlog="$base_dir/.outlog"

verbose=false

declare -A graphEnvs
graphEnvs['gnome']="gnome gdm" # also 'gnome-extra'
graphEnvs['lxqt']="lxqt sddm" # also 'lxqt-config lxdm'
graphEnvs['kde_plasma']="plasma-meta sddm"
graphEnvs['xfce']="xfce4 xdm" # also 'xfce4-goodies lightdm'
graphEnvs['mate']="mate lightdm" # also 'mate-extra'
graphEnvs['cinnamon']="cinnamon lightdm" # also 'cinnamon translations'
graphEnvs['deepin']="deepin lightdm" # also 'deepin-extra'
graphEnvs['enlightenment']="enlightenment lightdm" # also 'gdm'
graphEnvs['budgie']="budgie-desktop lightdm"

declare -A packageBundle
packageBundle['minimal']=""
packageBundle['gurgui']="linux-headers base-devel net-tools nmap tmux alacritty neovim ttf-firacode-nerd nodejs zip unzip p7zip wireshark-qt john hashcat subbrute sudo spectacle arp-scan openssl git cmake make gcc wget"
packageBundle['devel']="dotnet base-devel perl ruby nodejs"

# + New system vars
locale="es_ES.UTF-8"
timezone="Atlantic/Canary"
kblayout="es"

mountpoint="/mnt"
fdiskcmd=""

DISK=""
DISK_SIZE=0
AVAILABLE=0

BOOT_SIZE=1048576 # 1GB (kb) 
SWAP_SIZE=8388608 # 8GB (kb)
ROOT_SIZE=0 # (kb)
HOME_SIZE=0 # (kb)

BOOT_PATH=""
SWAP_PATH=""
ROOT_PATH=""
HOME_PATH=""

partitionScheme="gpt"   # gpt|mbr
partitionLayout="basic" # basic|advanced

hostname="arch1to"

user="admin"
pass=""
shell="/bin/bash"
nopasswd=false

enableGraphics=false
graphPack="" # an existing key from graphEnvs with the desired GE + DM
graphicalEnvironment=""
displayManager=""

kernel=linux # https://wiki.archlinux.org/title/Kernel#Officially_supported_kernels
supportedKernels="linux linux-lts linux-hardened linux-rt linux-zen"

network=networkmanager
firewall=nftables # nftables|iptables
enableFirewall=true

# base & linux-firmware: essential packages - https://wiki.archlinux.org/title/Installation_guide#Install_essential_packages
# grub: bootloader
# sudo: allows adding the default sudoer on /etc/sudoers to show all contents do "pacman -Fy && pacman -Fl sudo" 
packagesToInstall="base linux-firmware grub sudo"

#  - New System vars

# - Variables

# + Functions

cleanup_cmd=("rm $outlog $errlog &>/dev/null")
function __ctrl_c_handler(){
  printf -- "\n-- Running cleanup\n"
  for i in "${cleanup_cmd[@]}"; do 
    printf "\t'%s'\n" "$i"
  done
  exit 0
}

function usage(){
  cat << EOF 
# Arch autoinstall script 
# Author: Airán 'Gurgui' Gómez
# Description: Script to automatise arch linux installation

Usage: ./garch.sh [subopts]

= Subopts =

** general **
-h | --help : display this message and exit
-v | --verbose : be more verbose

** configuration **
-j | --json <path> : use file to load configuration

note: subopts set after the json is loaded will get overriden
e.g ./garch.sh --user gurgui -j conf.json # 'gurgui' will get overriden by whatever value the json has

** host **
-host | --hostname <hostname> : set hostname - default "arch1t0"

** user **
-u | --user <user>   : set sudoer username - default: "admin"
-s | --shell <path>  : set sudoer shell - default "/bin/bash"
-nopass | --nopass   : set NOPASSWD on user, meaning sudo commands won't prompt for a password 

** firewall **
-fw | --firewall <iptables|nftables> : set desired firewall to setup 

** disk **
-d      | --disk <path> : set disk - by default garch will automaticly look for disks in the system and prompt
-mnt    | --mountpoint <path> : set mountpoint - default "/mnt"
-mbr    | --mbr : use mbr partitioning table - default "gpt"
-gpt    | --gpt : use gpt partitioning table - default "gpt"
-swap   | --swapsize <int>G|M|K|B : set swap partition size  
-boot   | --bootsize <int>G|M|K|B : set boot partition size 
-layout | --layout <basic|advanced> : set partition layout (splitted /home or all in /)

** packages **
-kernel | --kernel <linux|linux-lts|linux-hardened|linux-rt|linux-zen> : set kernel - default 'linux'
-bundle | --package-bundle <minimal|gurgui|devel> : bundle of tools to install - default 'gurgui'
-extra  | --extra-packages <csv> : packages to install

** graphics **
-graphics | --graphics : install and enable graphics - default false
EOF
}

#    + Graphical environment setup
function setupGraphicalEnvironment(){
  if [[ -z "$graphicalEnvironment" || -z "$displayManager" ]]; then
    read -r -p "[?] Do you want to setup a graphical environment? y/n " ans
  
    if [[ "${ans,,}" != "y" && "${ans,,}" != "yes" ]]; then
      exit 1
    fi
    
    n=0
    for i in ${!graphEnv[@]}; do
     # Display options
     dMan=$(echo ${graphEnv[$i]} | cut -d' ' -f2)
     printf " %i - %s - %s\n" "$n" "$i" "$dMan"
     (( ++n ))
    done
    
    read -r -p "-- Choice: " ans
    
    if (( ans > $n-1 )); then
      printf "[-] Choice must be between 0 and %i\n" "$((n-1))"
      exit 1
    fi
    
    n=0
    
    # Assign user choice to the variable
    for i in "${!graphEnv[@]}"; do
      if (( $n == ans )); then
        graphicalEnvironment=$(cut -d ' ' -f 1 <<< "${graphEnv[$i]}" )
        displayManager=$(cut -d ' ' -f 2 <<< "${graphEnv[$i]}" )
      fi
      (( ++n ))
    done
  fi
} 
#    - Graphical environment setup

#    + Disk functions
function __set_fdiskCommandGPT(){
 fdiskcmd+="g\\n" # Create GPT disklabel
 fdiskcmd+="n\\n\\n\\n+""$BOOT_SIZE""K\\nt\\nuefi\\n"     # Create boot partition
 fdiskcmd+="n\\n\\n\\n+""$SWAP_SIZE""K\\nt\\n2\\nswap\\n" # Create swap partition

 if [ "${partitionLayout,,}" == "basic" ]; then
  fdiskcmd+="n\\n\\n\\n\\nt\\n3\\nlinux\\n" # Root partition
 elif [ "${partitionLayout,,}" == "advanced" ]; then
  fdiskcmd+="n\\n\\n\\n+""$ROOT_SIZE""K\\nt\\n3\\n23\\n" # Root partition - Type code 23 = linux root (x86-64)
  fdiskcmd+="n\\n\\n\\n\\nt\\n4\\nlinux\\n"     # Home partition - Type code 42 = linux home
 fi
}

function __set_fdiskCommandMBR(){
  fdiskcmd="o\\n" # Create DOS (MBR) disklabel
  fdiskcmd+="n\\n\\n\\n\\n+""$BOOT_SIZE""K\\nt\\nlinux\\na\\n" # Create boot partition and mark as bootable
  fdiskcmd+="n\\n\\n\\n\\n+""$SWAP_SIZE""K\\nt\\n2\\nswap\\n"  # Create swap partition

  if [ "${partitionLayout,,}" == "basic" ]; then
    fdiskcmd+="n\\n\\n\\n\\n\\nt\\n3\\nlinux\\n"
  elif [ "${partitionLayout,,}" == "advanced" ]; then
    fdiskcmd+="n\\n\\n\\n\\n+""$ROOT_SIZE""K\\nt\\n3\\nlinux\\n"
    fdiskcmd+="n\\np\\n\\n\\nt\\n4\\nlinux\\n"
  fi
}

function __set_TargetDisk(){
  local availableDisks=($(lsblk -dn -o PATH,SIZE | grep -v "0B\|ram\|sr" | awk '{print $1}'))
  n=0

  printf -- "-- Looking for disks in the system...\n\n"
  
  for disk in ${availableDisks[@]}; do
    printf "    %i: %s\n" "$n" "$(lsblk -o PATH,SIZE,MODEL -dn $disk)" 
    ((++n))  
  done
  
  while true; do
    printf "\n"
    read -p "-- Choice: " ans
    if [[ $ans =~ ^[0-9]$ ]] && (( ans < ${#availableDisks[@]} && ans >= 0 )); then
      DISK=${availableDisks[ans]}  
      break
    else
      continue
    fi
  done
}

function __fail_mount(){
  printf "[-] Failed mounting '%s' on '%s' - exit code %i\n" "$1" "$2" "$?"
  exit 1
}
function __fail_umount(){
  printf "[-] Failed umounting '%s' - exit code %i\n" "$1" "$?"
  exit 1
}
function __fail_createdir(){
  printf "[-] Failed creating directory '%s' - exit code %i\n" "$1" "$?"
  exit 1
}
function __fail_mkfs(){
  printf "[-] Failed creating filesystem '%s' on '%s' - exit code %i\n" "$1" "$2" "$?"
  exit 1
}

function setupDisk(){

  if [[ "$DISK" =~ [0-9]$ ]]; then
    BOOT_PATH="$DISK"p1
    SWAP_PATH="$DISK"p2
    ROOT_PATH="$DISK"p3
  else
    BOOT_PATH="$DISK"1
    SWAP_PATH="$DISK"2
    ROOT_PATH="$DISK"3
  fi

  DISK_SIZE=$(( $(lsblk -o SIZE -bdn "$DISK") / 1024 ))
  AVAILABLE="$DISK_SIZE"

  for kilobytes in $BOOT_SIZE $SWAP_SIZE; do
    (( AVAILABLE -= "$kilobytes" ))
  done
  
  (( $AVAILABLE <= 0 )) && printf "[-] Not enough memory %lu kb for boot and %lu kb for swap\n[-] Aborting...\n" "$BOOT_SIZE" "$SWAP_SIZE" && exit 1 
  
  if [ "${partitionLayout}" == "advanced" ]; then
    ROOT_SIZE=$(( AVAILABLE / 100 * 40 )) # root:40% home:60%
    HOME_SIZE=$(( AVAILABLE - ROOT_SIZE ))
    if [[ "$DISK" =~ [0-9]$ ]]; then 
      HOME_PATH="$DISK"p4
    else
      HOME_PATH="$DISK"4
    fi
  else
    ROOT_SIZE="$AVAILABLE"
  fi

  # Check if target disk got swap ON
  grep -q "$DISK" /proc/swaps && swapoff "$SWAP_PATH" &>/dev/null
  
  # Umount partitions
  umount "$BOOT_PATH" &>/dev/null
  umount "$ROOT_PATH" &>/dev/null
  umount "$HOME_PATH" &>/dev/null
  
  # Check if target disk is mounted
  if df --output=source | grep -q "$DISK"; then 
    printf -- "-- Couldn't umount, exiting...\n" && exit 1
  fi

  case "${partitionScheme,,}" in
    gpt)
      command -v "mkfs.vfat" &>/dev/null || pacman -Sy &>/dev/null && pacman -S dosfstools --noconfirm &>/dev/null
      __set_fdiskCommandGPT
      ;;
    mbr)
      __set_fdiskCommandMBR
      ;;
    *)
      printf "[-] Detected wrong partitioning scheme '%s'\n" "${partitionScheme,,}" && exit 1
      ;;
  esac

  fdiskcmd+="w\\n"
  
  # Show the disk layout to be applied
  cat << EOF
################### Disk layout ######################
                                                    
    PART          PATH            SIZE               
    boot          $BOOT_PATH    $(( BOOT_SIZE )) Kb 
    swap          $SWAP_PATH    $(( SWAP_SIZE )) Kb 
    root          $ROOT_PATH    $(( ROOT_SIZE )) Kb 
EOF

  (( $HOME_SIZE > 0 )) && printf "    home          %s    %s Kb\n" "$HOME_PATH" "$HOME_SIZE"

  printf "\n######################################################\n\n"
  # Ask for confirmation since disk wiping / partition erasing will be made
  read -r -p "-- WARNING - This will erase signatures from existing disk and delete partitions, continue? y/n: " ans
  if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then 
    exit 0 
  fi
  
  # Wipe existing signatures and partition table entries
  sfdisk --delete "$DISK" &>/dev/null
  wipefs --force --all "$DISK" &>/dev/null

  # Partition the disk
  echo -e "$fdiskcmd" | fdisk -w always -W always "$DISK" &>/dev/null

  if (( $? == 1 )); then
    printf "[-] Disk partitioning failed\n"
    exit 1
  fi

  partprobe "$DISK" &>/dev/null 1>>$outlog 2>>$errlog || { printf "[-] Partprobe failed before partitioning the disk"; exit 1; }

  # Create root and swap filesystems since they will be the same for both mbr | gpt 
  mkfs.ext4 -F "$ROOT_PATH" 1>>$outlog 2>>$errlog || __fail_mkfs "ext4" "$ROOT_PATH"
  mkswap -f "$SWAP_PATH"    1>>$outlog 2>>$errlog || __fail_mkfs "swap" "$SWAP_PATH"

  # Mount the disk
  if [ "${partitionScheme,,}" == "mbr" ]; then
    # Create appropiate boot fs
    local boot_mountpoint="$mountpoint/boot"
    mkfs.ext2 -F "$BOOT_PATH" 1>>$outlog 2>>$errlog || __fail_mkfs "ext2" "$BOOT_PATH"
    
    mount "$ROOT_PATH" "$mountpoint" 1>>$outlog 2>>$errlog || __fail_mount "$ROOT_PATH" "$mountpoint"
    mkdir -p "$boot_mountpoint" 1>>$outlog 2>>$errlog || __fail_createdir "$boot_mountpoint"
    mount "$BOOT_PATH" "$boot_mountpoint" 1>>$outlog 2>>$errlog || __fail_mount "$BOOT_PATH" "$boot_mountpoint"   

    if [ "${partitionLayout}" == "advanced" ]; then
      local home_mountpoint="$mountpoint/home"
      mkfs.ext4 -F "$HOME_PATH" 1>>$outlog 2>>$errlog || __fail_mkfs "ext4" "$HOME_PATH" 

      mkdir -p "$home_mountpoint" 1>>$outlog 2>>$errlog || __fail_createdir "$home_mountpoint"
      mount "$HOME_PATH" "$home_mountpoint" 1>>$outlog 2>>$errlog || __fail_mount "$HOME_PATH" "$home_mountpoint"
    fi
  elif [ "${partitionScheme,,}" == "gpt" ]; then
    # Create appropiate boot fs
    mkfs.vfat -F32 "$BOOT_PATH" 1>>$outlog 2>>$errlog || __fail_mkfs "FAT32" "$BOOT_PATH"

    local boot_mountpoint="$mountpoint/boot/efi"

    mount "$ROOT_PATH" "$mountpoint" 1>>$outlog 2>>$errlog || __fail_mount "$ROOT_PATH" "$mountpoint"
    mkdir -p "$boot_mountpoint" 1>>$outlog 2>>$errlog || __fail_createdir "$boot_mountpoint"
    mount "$BOOT_PATH" "$boot_mountpoint" 1>>$outlog 2>>$errlog || __fail_mount "$BOOT_PATH" "$boot_mountpoint"

    if [ "${partitionLayout,,}" == "advanced" ]; then
      local home_mountpoint="$mountpoint/home"

      mkfs.ext4 -F "$HOME_PATH" 1>>$outlog 2>>$errlog || __fail_mkfs "ext4" "$HOME_PATH"

      mkdir -p "$home_mountpoint" 1>>$outlog 2>>$errlog || __fail_createdir "$home_mountpoint"
      mount "$HOME_PATH" "$home_mountpoint" 1>>$outlog 2>>$errlog || __fail_mount "$HOME_PATH" "$home_mountpoint"
    fi
  fi

  # Enable swap
  swapon "$SWAP_PATH"

  partprobe "$DISK" &>/dev/null 1>>$outlog 2>>$errlog || { printf "[-] Partprobe failed after partitioning the disk"; exit 1 ;}

  # Print disk layout after being partitioned
  fdisk -o device,size,type -l "$DISK" | grep -E "^(/|Disk $DISK|Disklabel|Disk identifier)"
} 
#    - Disk functions


function setupNetwork(){
  echo "-- Unimplemented setupNetwork()"
}

function setupFirewall(){
  $enableFirewall || return 

  # Package gets added to $packagesToInstall on function parse() 
  # pacstrap -GU "$mountpoint" "$firewall"

  if [ "${firewall,,}" == "iptables" ]; then
    # Setup iptables  
cat << EOF > "$mountpoint/etc/iptables.rules"
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Early drop of invalid connections
-I INPUT -m state --state INVALID -j DROP

# Allow established and related connections
-I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow specific incoming services (SSH, HTTP, HTTPS, DNS)
-A INPUT -p tcp --dport 22 -j ACCEPT -m comment --comment "allow ssh"
-A INPUT -p tcp --dport 80 -j ACCEPT -m comment --comment "allow http"
-A INPUT -p tcp --dport 443 -j ACCEPT -m comment --comment "allow https"
-A INPUT -p udp --dport 53 -j ACCEPT -m comment --comment "allow dns"

# Allow outgoing connections (established only)
-A FORWARD -m state --state ESTABLISHED -j ACCEPT

# Allow loopback traffic
-A INPUT -i lo -j ACCEPT
COMMIT
EOF
    arch-chroot "$mountpoint" /bin/bash -c "systemctl enable iptables"
  elif [ "${firewall,,}" == "nftables" ]; then
    # Setup nftables
    arch-chroot "$mountpoint" /bin/bash -c "mv /etc/nftables.conf /etc/nftables.conf.original"
    cat << EOF > "$mountpoint/etc/nftables.conf"
#!/usr/bin/nft -f

# File generated by garch.sh - https://github.com/Gurguii/arch-autoinstall
# original /etc/nftables.conf renamed to /etc/nftables.conf.original

table inet filter
delete table inet filter
table inet filter {
        chain input {
                type filter hook input priority filter; policy drop;
                ct state invalid drop comment "early drop of invalid connections"
                ct state {established, related} accept comment "allow tracked connections"

                tcp sport 22 accept comment "allow ssh"
                tcp sport 80 accept comment "allow http"
                tcp sport 443 accept comment "allow https"
                udp sport 53 accept comment "allow dns"
                tcp dport 22 accept comment "allow sshd"

                ip protocol icmp accept comment "allow icmp4"
                iifname "lo" accept comment "allow loopback"
        }

        chain forward {
                type filter hook forward priority filter; policy drop;
        }
}
EOF
    arch-chroot "$mountpoint" /bin/bash -c "systemctl enable nftables"
  else
    printf "[-] Unsupported firewall '%s' - omitting setup\n" "$firewall"
  fi
}

function setupArch(){
  # dosfstools: mkfs.vfat -F 32
  # efibootmgr: manage efi boot entries
  if [[ "$partitionScheme" == "gpt" ]]; then
    packagesToInstall="$packagesToInstall efibootmgr"
  fi

  # - Install packages
  cmd="pacstrap -K "$mountpoint" "$packagesToInstall"" 
  printf -- "-- Installing packages on new system - %s\n" "$cmd" 
  $cmd &>/dev/null

  if (( $? != 0 )) then
    printf "[-] Installing packages failed\n"
    exit 1
  fi
  
  # - Do some configuration in the new system
  cat << EOF > "$mountpoint/root/garch_autoinstall.sh" 
#!/bin/bash
# Gurgui's arch autoinstall script

# Exit on error
set -e

# Upgrade system 
pacman -Syuu --noconfirm

# Set hostname
echo "$hostname" > /etc/hostname

# Set vconsole keyboard layout
echo "KEYMAP=$kblayout" > /etc/vconsole.conf

# Set locale
sed -i "s/^#$locale/$locale/" /etc/locale.gen
locale-gen

# Set timezone
# timedatectl set-timezone "$timezone"

# Create sudoer
useradd -m "$user" -s "$shell"

echo -e "# Gurgui automated script\n"$user" ALL=(ALL : ALL) $($nopasswd && printf "NOPASSWD: %s " "$user")ALL" >> /etc/sudoers

# Install the bootloader
grub-install "$BOOT_PATH"

# Update grub config file for next boots
grub-mkconfig -o /boot/grub/grub.cfg 
EOF
  arch-chroot "$mountpoint" /bin/bash -c "chmod +x /root/garch_autoinstall.sh; ./root/garch_autoinstall.sh; rm /root/garch_autoinstall.sh"

  # - Generate new system's fstab
  genfstab -U "$mountpoint" > "$mountpoint/etc/fstab"
  # - Comment out boot entry
  sed -i "s%$BOOT_PATH%#$BOOT_PATH%" "$mountpoint/etc/fstab"
  # Set user password
  printf -- "-- User: '%s'\n" "$user"
  passwd -R "$mountpoint" "$user"

  setupFirewall # Will inmediatly return if $enableFirewall == false

  # TODO - function setupNvidia()

  # Umount the disk and turn swap off
  for partition in "$HOME_PATH" "$BOOT_PATH" "$ROOT_PATH"; do
    if [ -d "$partition" ]; then 
      umount "$partition" &>/dev/null || __fail_umount "$partition"
    fi
  done
  swapoff "$SWAP_PATH" &>/dev/null

  read -r -p "[+] Installation done, reboot now? y/n " res
  
  if [[ ${res,,} == "y" || ${res,,} == "yes" ]]; then
    reboot
  fi
}

function checkVariables(){
  # -- mountpoint
  if [ ! -e "$mountpoint" ]; then
    printf "[-] mountpoint '%s' doesn't exist\n" "$mountpoint" && exit 1
  fi

  if df --output=source | grep -Eq "^$mountpoint$"; then
    umount "$mountpoint" || __fail_umount "$mountpoint"
  fi

  # -- firewall
  if $enableFirewall; then
    if [ -z "$firewall" ]; then
      read -rp "[+] desired firewall (iptables, nftables): " firewall
    fi

    case "${firewall,,}" in 
      "nftables" | "iptables" ) packagesToInstall="$packagesToInstall $firewall" ;;
      * ) printf "[-] Firewall '%s' is not among valid options - [iptables,nftables]\n" "$firewall" && exit 1 ;;
    esac
  fi

  # -- kernel choice
  local exist=false
  for k in $supportedKernels; do
    if [ "$k" == "$kernel" ]; then
      exist=true && break      
    fi
  done

  if [ $exist == false ]; then
    printf "[-] Kernel '%s' is not among valid options - [%s]\n" "$kernel" "$supportedKernels" && exit 1
  else
    packagesToInstall="$kernel $packagesToInstall"
  fi

  # -- disk
  if [[ -z "$DISK" ]]; then
    __set_TargetDisk
  fi

  if ! lsblk "$DISK" &>/dev/null; then 
    printf "[-] Path '%s' is not a block device\n" "$DISK" && exit 1
  fi

  case "${partitionLayout,,}" in
    basic | advanced ) ;;
    * ) printf "[-] Invalid partition layout\nbasic: / boot swap (3 partitions)\nadvanced: / /home boot swap (4 partitions)\n" && exit 0
  esac
}

function loadJson(){
  # $1 - path to json file with configuration
  if ! command -v jq &>/dev/null; then
    read -rp "[+] Need to install 'jq' in order to use -j | --json, proceed? y/n " ans
    if [[ "${ans,,}" == "y" || "${ans,,}" = "yes" ]]; then
      pacman -S --noconfirm jq &>/dev/null || printf "[+] Couldn't install, ensure proper permissions or install it yourself 'pacman -S --noconfirm jq'\n" && exit 0
    else
      exit 0
    fi
  fi

  local config="$1"

  [ -e "$config" ] || { printf "[+] Config '%s' doesn't exist\n"; exit 1; }

  kblayout=$(jq -r ".kblayout" "$config")
  mountpoint=$(jq -r ".mountpoint" "$config")
  
  DISK=$(jq -r ".disk.path" "$config")
  partitionScheme=$(jq -r ".disk.scheme" "$config")
  partitionLayout=$(jq -r ".disk.layout" "$config")
  BOOT_SIZE=$(jq -r ".disk.boot_size" "$config")
  BOOT_PATH=$(jq -r ".disk.boot_path" "$config")
  SWAP_SIZE=$(jq -r ".disk.swap_size" "$config")
  SWAP_PATH=$(jq -r ".disk.swap_path" "$config")
  ROOT_SIZE=$(jq -r ".disk.root_size" "$config")
  ROOT_PATH=$(jq -r ".disk.root_path" "$config")
  HOME_SIZE=$(jq -r ".disk.home_size" "$config")
  HOME_PATH=$(jq -r ".disk.home_path" "$config")
  
  user=$(jq -r ".user" "$config")
  locale=$(jq -r ".locale" "$config")
  timezone=$(jq -r ".timezone" "$config")
  hostname=$(jq -r ".hostname" "$config")
  shell=$(jq -r ".shell" "$config")
  nopasswd=$(jq -r ".nopasswd" "$config")
  enableGraphics=$(jq -r ".enableGraphics" "$config")
  graphPack=$(jq -r ".graphPack" "$config")
  kernel=$(jq -r ".kernel" "$config")
  network=$(jq -r ".network" "$config")
  enableFirewall=$(jq -r ".enableFirewall" "$config")
  firewall=$(jq -r ".firewall" "$config")
  extra=$(jq -r ".extra" "$config")
  packagesToInstall+=" ${packageBundle[$(jq -r ".bundle" "$config")]}"
}

function __retrieve_size(){
  # $1 - user input, e.g 5G, 4M, 3K, 2B
  size="${1:0: -1}"
  unit="${1: -1}"

  case "${unit,,}" in
    g ) printf -- "%lu" "$(( $size * 1024 * 1024 ))" ;;
    m ) printf -- "%lu" "$(( $size * 1024  ))" ;;
    k ) printf -- "%lu" "$size" ;;
    b ) printf -- "%lu" "$(( $size / 1024 ))" ;;
    * ) printf -- "-1"
  esac
}

function parse(){
 for (( i = 0 ; i < $argc ; ++i )); do
  opt="${args[i],,}"
  if   [[ "$opt" == "-h" || "$opt" == "--help" ]]; then
    usage && exit 0
  elif [[ "$opt" == "-v" || "$opt" == "--verbose" ]]; then
    verbose=true
  elif [[ "$opt" == "-d" || "$opt" == "--disk" ]]; then
    DISK="${args[++i]}"
  elif [[ "$opt" == "-u" || "$opt" == "--user" ]]; then
    user="${args[++i]}"
  elif [[ "$opt" == "-p" || "$opt" == "--pass" ]]; then
    pass="${args[++i]}"
  elif [[ "$opt" == "-s" || "$opt" == "--shell" ]]; then
    shell="${args[++i]}"
  elif [[ "$opt" == "-host" || "$opt" == "--hostname" ]]; then
    hostname="${args[++i]}"
  elif [[ "$opt" == "-k" || "$opt" == "--kernel" ]]; then
    kernel="${args[++i]}"
  elif [[ "$opt" == "-fw" || "$opt" == "--firewall" ]]; then
    firewall="${args[++i]}"
  elif [[ "$opt" == "-mbr" || "$opt" == "--mbr" ]]; then
    partitionScheme="mbr"
  elif [[ "$opt" == "-gpt" || "$opt" == "--gpt" ]]; then
    partitionScheme="gpt"
  elif [[ "$opt" == "-extra" || "$opt" == "--extra-packages" ]]; then
    packagesToInstall+=" $(echo "${args[++i]}" | tr ',' ' ')"
  elif [[ "$opt" == "-bundle" || "$opt" == "--package-bundle" ]]; then
    packagesToInstall+=" ${packageBundle["${args[++i]}"]}"
  elif [[ "$opt" == "-G" || "$opt" == "--set-graphics" ]]; then
    graphPack="${args[++i]}"
  elif [[ "$opt" == "-graphics" || "$opt" == "--graphics" ]]; then
    enableGraphics=true
  elif [[ "$opt" == "-nopass" || "$opt" == "--nopass" ]]; then
    nopasswd=true
  elif [[ "$opt" == "-mnt" || "$opt" == "--mountpoint" ]]; then
    mountpoint="${args[++i]}"
  elif [[ "$opt" == "-swap" || "$opt" == "--swapsize" ]]; then
    SWAP_SIZE=$(__retrieve_size "${args[++i]}")
    (( $SWAP_SIZE <= 0 )) && printf "[-] swap size '%s' must be a positive integer > 0\n " "${args[++i]}" && exit 1
    (( ++i ))
  elif [[ "$opt" == "-boot" || "$opt" == "--bootsize" ]]; then
    BOOT_SIZE=$(__retrieve_size "${args[++i]}")
    (( $BOOT_SIZE <= 0 )) && printf "[-] boot size '%s' must be a positive integer > 0\n" "${args[++i]}" && exit 1 
    (( ++i ))
  elif [[ "$opt" == "-layout" || "$opt" == "--layout" ]]; then
    partitionLayout="${args[++i]}"
  elif [[ "$opt" == "-j" || "$opt" == "--json" ]]; then
    loadJson "${args[++i]}"
  else 
    printf "[-] Unknown option '%s'\n" "$opt"
  fi
 done

 checkVariables
}

function main(){
  trap SIGINT # clear SIGINT handlers
  trap __ctrl_c_handler SIGINT # handler

  # Empty any previous logs
  date > $errlog
  date > $outlog

  # Parse arguments (override, checks etc.)
  parse
  
  # Get target disk interactively and set DISK | DISK_SIZE variables
  setupDisk

  # Set desired graphical environment if graphics=true
  $enableGraphics && setupGraphicalEnvironment

  # Set up the new system basic config + bootloader
  setupArch

  exit 0
}

# - Functions
main