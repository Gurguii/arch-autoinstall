#!/bin/bash 

# + Variables
argc=$#
read -a args <<< "$@"

baseDir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
errlog="$baseDir/.errlog"
outlog="$baseDir/.outlog"

verbose=false

declare -A graphEnvs
graphEnvs['gnome']="gnome gdm" # also 'gnome-extra'
graphEnvs['lxqt']="lxqt sddm" # also 'lxqt-config lxdm'
graphEnvs['kde_plasma']="plasma-meta sddm"
graphEnvs['xfce']="xfce4 lxdm" # also 'xfce4-goodies lightdm'

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

disk=""
diskSize=0
AVAILABLE=0

bootSize=1048576 # 1GB (kb) 
swapSize=8388608 # 8GB (kb)
rootSize=0 # (kb)
homeSize=0 # (kb)

bootPath=""
swapPath=""
rootPath=""
homePath=""

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
enableOsprober=false
#  - New System vars

# - Variables

# + Functions


cleanup_cmd=("rm $outlog $errlog &>/dev/null")
function cleanup(){
  for cmd in "${cleanup_cmd[@]}"; do 
    $cmd &>/dev/null
    #printf "\t'%s'\n" "$cmd"
  done
  exit 0
}

function __ctrl_c_handler(){
  printf -- "\n-- Cleaning up\n"
  cleanup
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

** bootloader **
-oscheck | --osprober : check for additional OSes when running grub-install
note: if you want to look for Windows installations, make sure you add '-extra ntfs-3g' to the command line
EOF
}

#    + Graphical environment setup
function __chooseGraphicalEnvironment(){
  local n=0
  local dMan
  if [[ -z "$graphicalEnvironment" || -z "$displayManager" ]]; then
    for i in "${!graphEnvs[@]}"; do
     # Display options
     dMan=$(echo ${graphEnvs[$i]} | cut -d' ' -f2)
     printf " %i - %s - %s\n" "$n" "$i" "$dMan"
     (( ++n ))
    done
    
    read -r -p "-- Choice: " ans
    
    if (( ans > n-1 )); then
      printf "[-] Choice must be between 0 and %i\n" "$((n-1))"
      exit 1
    fi
    
    n=0
    # Assign user choice to the variable
    for i in "${!graphEnvs[@]}"; do
      if (( n == ans )); then
        graphicalEnvironment=$(cut -d ' ' -f 1 <<< "${graphEnvs[$i]}" )
        displayManager=$(cut -d ' ' -f 2 <<< "${graphEnvs[$i]}" )
        break
      fi
      (( ++n ))
    done
  fi
} 

#    - Graphical environment setup

#    + Disk functions
function __set_fdiskCommandGPT(){
 fdiskcmd+="g\\n" # Create GPT disklabel
 fdiskcmd+="n\\n\\n\\n+""$bootSize""K\\nt\\nuefi\\n"     # Create boot partition
 fdiskcmd+="n\\n\\n\\n+""$swapSize""K\\nt\\n2\\nswap\\n" # Create swap partition

 if [ "${partitionLayout,,}" == "basic" ]; then
  fdiskcmd+="n\\n\\n\\n\\nt\\n3\\nlinux\\n" # Root partition
 elif [ "${partitionLayout,,}" == "advanced" ]; then
  fdiskcmd+="n\\n\\n\\n+""$rootSize""K\\nt\\n3\\n23\\n" # Root partition - Type code 23 = linux root (x86-64)
  fdiskcmd+="n\\n\\n\\n\\nt\\n4\\nlinux\\n"     # Home partition - Type code 42 = linux home
 fi
}

function __set_fdiskCommandMBR(){
  fdiskcmd="o\\n" # Create DOS (MBR) disklabel
  fdiskcmd+="n\\n\\n\\n\\n+""$bootSize""K\\nt\\nlinux\\na\\n" # Create boot partition and mark as bootable
  fdiskcmd+="n\\n\\n\\n\\n+""$swapSize""K\\nt\\n2\\nswap\\n"  # Create swap partition

  if [ "${partitionLayout,,}" == "basic" ]; then
    fdiskcmd+="n\\n\\n\\n\\n\\nt\\n3\\nlinux\\n"
  elif [ "${partitionLayout,,}" == "advanced" ]; then
    fdiskcmd+="n\\n\\n\\n\\n+""$rootSize""K\\nt\\n3\\nlinux\\n"
    fdiskcmd+="n\\np\\n\\n\\nt\\n4\\nlinux\\n"
  fi
}

function __chooseDiskFromMenu() {
  local upArrow=$'\e[A' downArrow=$'\e[B'
  local diskTable diskList count
  local cpos=0  index=0

  diskTable=$(lsblk -And -o PATH,SIZE,MODEL,FSTYPE | grep -v "ram\|sr")
  diskList=($(lsblk -And -o PATH | grep -v "ram\|sr"))
  count=$(wc -l <<< $diskTable)
  
  printf "== Select disk ==\n"
  while true
  do
      # list all options (option list is zero-based)
      index=0 
      while read -r line; 
      do
          if [ "$index" == "$cpos" ]
            then echo -e " >\e[7m$line\e[0m" # mark & highlight the current option
            else echo "  $line"
          fi
          index=$(( index + 1 ))
      done <<< "$diskTable"
      read -rs -n3 key # wait for user to key in arrows or ENTER
      if [[ $key == "$upArrow" ]]; then
        # up arrow
        (( --cpos  ))
        (( cpos <= 0 )) && cpos=0
      elif [[ $key == "$downArrow" ]] then 
        # down arrow
        (( ++cpos ))
        (( cpos >= count )) && cpos=$(( count - 1 ))
      elif [[ $key == "" ]]; then
        disk="${diskList[cpos]}"
        break
      fi
      echo -en "\e[${count}A" # go up to the beginning to re-render
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

  if [[ "$disk" =~ [0-9]$ ]]; then
    bootPath="$disk"p1
    swapPath="$disk"p2
    rootPath="$disk"p3
  else
    bootPath="$disk"1
    swapPath="$disk"2
    rootPath="$disk"3
  fi

  diskSize=$(( $(lsblk -o SIZE -bdn "$disk") / 1024 ))
  AVAILABLE="$diskSize"

  for kilobytes in $bootSize $swapSize; do
    (( AVAILABLE -= "$kilobytes" ))
  done
  
  (( AVAILABLE <= 0 )) && printf "[-] Not enough memory %lu kb for boot and %lu kb for swap\n[-] Aborting...\n" "$bootSize" "$swapSize" && exit 1 
  
  if [ "${partitionLayout}" == "advanced" ]; then
    rootSize=$(( AVAILABLE * 40 / 100  )) # root:40% home:60%
    homeSize=$(( AVAILABLE - rootSize ))
    if [[ "$disk" =~ [0-9]$ ]]; then 
      homePath="$disk"p4
    else
      homePath="$disk"4
    fi
  else
    rootSize="$AVAILABLE"
  fi

  # Check if target disk got swap ON
  grep -q "$disk" /proc/swaps && swapoff "$swapPath" &>/dev/null
  
  # Umount partitions
  umount "$bootPath" &>/dev/null
  umount "$rootPath" &>/dev/null
  umount "$homePath" &>/dev/null
  
  # Check if target disk is mounted
  if df --output=source | grep -q "$disk"; then 
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
    boot          $bootPath    $(( bootSize )) Kb 
    swap          $swapPath    $(( swapSize )) Kb 
    root          $rootPath    $(( rootSize )) Kb 
EOF

  (( homeSize > 0 )) && printf "    home          %s    %s Kb\n" "$homePath" "$homeSize"

  printf "\n######################################################\n\n"
  # Ask for confirmation since disk wiping / partition erasing will be made
  read -r -p "-- WARNING - This will erase signatures from existing disk and delete partitions, continue? y/n: " ans
  if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then 
    exit 0 
  fi
  
  # Wipe existing signatures and partition table entries
  sfdisk --delete "$disk" &>/dev/null
  wipefs --force --all "$disk" &>/dev/null

  # Partition the disk
  echo -e "$fdiskcmd" | fdisk -w always -W always "$disk" &>/dev/null

  if (( $? == 1 )); then
    printf "[-] Disk partitioning failed\n"
    exit 1
  fi

  partprobe "$disk" 1>>"$outlog" 2>>"$errlog" || { printf "[-] Partprobe failed before partitioning the disk"; exit 1; }

  # Create root and swap filesystems since they will be the same for both mbr | gpt 
  mkfs.ext4 -F "$rootPath" 1>>"$outlog" 2>>"$errlog" || __fail_mkfs "ext4" "$rootPath"
  mkswap -f "$swapPath"    1>>"$outlog" 2>>"$errlog" || __fail_mkfs "swap" "$swapPath"

  # Mount the disk
  if [ "${partitionScheme,,}" == "mbr" ]; then
    # Create appropiate boot fs
    local boot_mountpoint="$mountpoint/boot"
    mkfs.ext2 -F "$bootPath" 1>>"$outlog" 2>>"$errlog" || __fail_mkfs "ext2" "$bootPath"
    
    mount "$rootPath" "$mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_mount "$rootPath" "$mountpoint"
    mkdir -p "$boot_mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_createdir "$boot_mountpoint"
    mount "$bootPath" "$boot_mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_mount "$bootPath" "$boot_mountpoint"   

    if [ "${partitionLayout}" == "advanced" ]; then
      local home_mountpoint="$mountpoint/home"
      mkfs.ext4 -F "$homePath" 1>>"$outlog" 2>>"$errlog" || __fail_mkfs "ext4" "$homePath" 

      mkdir -p "$home_mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_createdir "$home_mountpoint"
      mount "$homePath" "$home_mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_mount "$homePath" "$home_mountpoint"
    fi
  elif [ "${partitionScheme,,}" == "gpt" ]; then
    # Create appropiate boot fs
    mkfs.vfat -F32 "$bootPath" 1>>"$outlog" 2>>"$errlog" || __fail_mkfs "FAT32" "$bootPath"

    local boot_mountpoint="$mountpoint/boot/efi"

    mount "$rootPath" "$mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_mount "$rootPath" "$mountpoint"
    mkdir -p "$boot_mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_createdir "$boot_mountpoint"
    mount "$bootPath" "$boot_mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_mount "$bootPath" "$boot_mountpoint"

    if [ "${partitionLayout,,}" == "advanced" ]; then
      local home_mountpoint="$mountpoint/home"

      mkfs.ext4 -F "$homePath" 1>>"$outlog" 2>>"$errlog" || __fail_mkfs "ext4" "$homePath"

      mkdir -p "$home_mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_createdir "$home_mountpoint"
      mount "$homePath" "$home_mountpoint" 1>>"$outlog" 2>>"$errlog" || __fail_mount "$homePath" "$home_mountpoint"
    fi
  fi

  # Enable swap
  swapon "$swapPath"

  partprobe "$disk" 1>>$outlog 2>>"$errlog" || { printf "[-] Partprobe failed after partitioning the disk"; exit 1 ;}

  # Print disk layout after being partitioned
  fdisk -o device,size,type -l "$disk" | grep -E "^(/|Disk $disk|Disklabel|Disk identifier)"
} 
#    - Disk functions

function setupGraphicalEnvironment(){
  $enableGraphics || return 

  arch-chroot "$mountpoint" /bin/bash -c "systemctl enable $graphicalEnvironment"
}

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
  else
    printf "[-] Unsupported firewall '%s' - omitting setup\n" "$firewall"
  fi

  # Enable firewall service (iptables required to be enabled, nftables will load rules)
  arch-chroot "$mountpoint" /bin/bash -c "systemctl enable $firewall"
}

function setupArch(){
  # dosfstools: mkfs.vfat -F 32
  # efibootmgr: manage efi boot entries
  if [[ "$partitionScheme" == "gpt" ]]; then
    packagesToInstall="$packagesToInstall efibootmgr"
  fi

  # - Install packages
  cmd="pacstrap -K $mountpoint $packagesToInstall"
  printf -- "-- Installing packages on new system - %s\n" "$cmd" | tee -a "$outlog"
  if ! $cmd 1>>"$outlog" 2>>"$errlog"; then
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

$($enableOsprober && echo "sed -i 's/^#GRUB_DISABLE_OS_PROBER/GRUB_DISABLE_OS_PROBER/' /etc/default/grub")

# Install the bootloader
grub-install "$bootPath"

# Update grub config file for next boots
grub-mkconfig -o /boot/grub/grub.cfg 
EOF
  arch-chroot "$mountpoint" /bin/bash -c "chmod +x /root/garch_autoinstall.sh; ./root/garch_autoinstall.sh; rm /root/garch_autoinstall.sh"

  # - Generate new system's fstab
  genfstab -U "$mountpoint" > "$mountpoint/etc/fstab"
  
  # - Comment out boot entry
  sed -i "s%$bootPath%#$bootPath%" "$mountpoint/etc/fstab"

  # Set user password
  printf -- "-- User: '%s'\n" "$user"
  passwd -R "$mountpoint" "$user"

  setupFirewall # Will inmediatly return if $enableFirewall == false
  setupGraphicalEnvironment
  # TODO - function setupNvidia()

  # Umount the disk and turn swap off
  for partition in "$homePath" "$bootPath" "$rootPath"; do
    if [ -d "$partition" ]; then 
      umount "$partition" 1>>"$outlog" 2>>"$errlog" || __fail_umount "$partition"
    fi
  done
  swapoff "$swapPath" &>/dev/null

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

  # -- graphics 
  if $enableGraphics; then
    __chooseGraphicalEnvironment
    packagesToInstall="$packagesToInstall $displayManager $graphicalEnvironment"
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
  [ -z "$disk" ] && __chooseDiskFromMenu

  if ! lsblk "$disk" &>/dev/null; then 
    printf "[-] Path '%s' is not a block device\n" "$disk" && exit 1
  fi

  case "${partitionLayout,,}" in
    basic | advanced ) ;;
    * ) printf "[-] Invalid partition layout\nbasic: / boot swap (3 partitions)\nadvanced: / /home boot swap (4 partitions)\n" && exit 0
  esac

  (( swapSize <= 0 )) && printf "[-] swap size '-%s Kb' must be a positive integer\n" "$swapSize" && exit 1
  (( bootSize <= 0 )) && printf "[-] boot size '-%s Kb' must be a positive integer > 0\n" "$bootSize" && exit 1 

  # -- osprober
  if [ $enableOsprober == true ]; then
    packagesToInstall="$packagesToInstall os-prober"
  fi
}

function loadJson(){
  # $1 - path to json file with configuration
  if ! command -v jq &>/dev/null; then
    read -rp "[+] Need to install 'jq' in order to use -j | --json, proceed? y/n " ans
    if [[ "${ans,,}" == "y" || "${ans,,}" = "yes" ]]; then
      pacman -Sy &>/dev/null
      pacman -S --noconfirm jq &>/dev/null || { printf "[+] Couldn't install, ensure proper permissions or install it yourself 'pacman -S --noconfirm jq'\n"; exit 0; }
    else
      exit 0
    fi
  fi

  local config="$1"

  [ -e "$config" ] || { printf "[+] Config '%s' doesn't exist\n" "$config" ; exit 1; }

  local json
  json=$(cat "$config")

  kblayout=$(jq -r ".kblayout" <<< "$json")
  mountpoint=$(jq -r ".mountpoint" <<< "$json")
  
  disk=$(jq -r ".disk.path" <<< "$json")
  partitionScheme=$(jq -r ".disk.scheme" <<< "$json")
  partitionLayout=$(jq -r ".disk.layout" <<< "$json")
  bootSize=$(jq -r ".disk.boot_size" <<< "$json")
  bootPath=$(jq -r ".disk.boot_path" <<< "$json")
  swapSize=$(jq -r ".disk.swap_size" <<< "$json")
  swapPath=$(jq -r ".disk.swap_path" <<< "$json")
  rootSize=$(jq -r ".disk.root_size" <<< "$json")
  rootPath=$(jq -r ".disk.root_path" <<< "$json")
  homeSize=$(jq -r ".disk.home_size" <<< "$json")
  homePath=$(jq -r ".disk.home_path" <<< "$json")
  
  user=$(jq -r ".user" <<< "$json")
  locale=$(jq -r ".locale" <<< "$json")
  timezone=$(jq -r ".timezone" <<< "$json")
  hostname=$(jq -r ".hostname" <<< "$json")
  shell=$(jq -r ".shell" <<< "$json")
  nopasswd=$(jq -r ".nopasswd" <<< "$json")
  enableGraphics=$(jq -r ".enableGraphics" <<< "$json")
  graphPack=$(jq -r ".graphPack" <<< "$json")
  kernel=$(jq -r ".kernel" <<< "$json")
  network=$(jq -r ".network" <<< "$json")
  enableFirewall=$(jq -r ".enableFirewall" <<< "$json")
  firewall=$(jq -r ".firewall" <<< "$json")
  extra=$(jq -r ".extra" <<< "$json")
  local bundle="$(jq -r ".bundle" <<< "$json")"
  if [ ! -z "$bundle" ]; then
    packagesToInstall+=" ${packageBundle[bundle]}"
  fi
  enableOsprober=$(jq -r ".enableOsprober" <<< "$json")
}

function __retrieve_size(){
  # $1 - user input, e.g 5G, 4M, 3K, 2B
  # $2 - outvar, size in Kilobytes
  size="${1:0: -1}"
  unit="${1: -1}"

  case "${unit,,}" in
    g ) printf -v $2 -- "%lu" "$(( size * 1024 * 1024 ))" ;;
    m ) printf -v $2 -- "%lu" "$(( size * 1024  ))" ;;
    k ) printf -v $2 -- "%lu" "$size" ;;
    b ) printf -v $2 -- "%lu" "$(( size / 1024 ))" ;;
    * ) printf -v $2 -- "-1"
  esac
}

function parseArgs(){
 for (( i = 0 ; i < $argc ; ++i )); do
  opt="${args[i],,}"
  if   [[ "$opt" == "-h" || "$opt" == "--help" ]]; then
    usage && exit 0
  elif [[ "$opt" == "-v" || "$opt" == "--verbose" ]]; then
    verbose=true
  elif [[ "$opt" == "-d" || "$opt" == "--disk" ]]; then
    disk="${args[++i]}"
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
    (( ++i ))
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
    __retrieve_size "${args[++i]}" swapSize
  elif [[ "$opt" == "-boot" || "$opt" == "--bootsize" ]]; then
    __retrieve_size "${args[++i]}" bootSize
  elif [[ "$opt" == "-layout" || "$opt" == "--layout" ]]; then
    partitionLayout="${args[++i]}"
  elif [[ "$opt" == "-j" || "$opt" == "--json" ]]; then
    loadJson "${args[++i]}"
  elif [[ "$opt" == "-oscheck" || "$opt" == --osprober ]]; then
    enableOsprober=true
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
  printf "Starting garch.sh %s\n" "$(date)" > "$errlog"
  printf "Starting garch.sh %s\n" "$(date)" > "$outlog"

  # Parse arguments (override, checks etc.)
  parseArgs
  
  # Get target disk interactively and set disk | disk_SIZE variables
  setupDisk

  # Set up the new system basic config + bootloader
  setupArch
  exit 0
}

# - Functions
main