#!/bin/bash 

# + Variables
argc=$#
args=($@)

verbose=false

keyboard_layout="es"
timezone="UTC+0"

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
# note: -> | linux base linux-firmware linux-headers grub networkmanager efibootmgr | <- packages will always be installed
packageBundle['minimal']=""
packageBundle['gurgui']="base-devel net-tools nmap neovim ttf-firacode-nerd nodejs zip unzip p7zip wireshark-qt john hashcat subbrute sudo"
packageBundle['devel']="base-devel perl ruby nodejs"

# + New system
mountpoint="/mnt"
mountcmd=()
fdiskcmd=""
DISK=""
DISK_SIZE=0
AVAILABLE=0
BOOTSIZE=1048576 # 1GB
SWAPSIZE=8388608 # 8GB
ROOTSIZE=0
HOMESIZE=0
grubBoot=""

partitionScheme="gpt"
partitionLayout="basic" # basic(/) advanced(/:/home)  

hostname="arch1to"

user="admin"
pass=""

enableGraphics=false
graphicalEnvironment=""
displayManager=""

packagesToInstall='linux base linux-firmware linux-headers grub networkmanager efibootmgr sudo'

extraPackages=""
# - Variables

# + Functions

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

** host **
-h | --hostname <hostname> : set hostname - default "arch1t0"

** user **
-u | --user <user> : set username for new system's sudoer - default: "admin"
-p | --pass <pass> : set password for new system's sudoer - default: "" (will get prompted)

** disk **
-mnt    | --mountpoint <mountpoint> : set mountpoint - default "/mnt"
-mbr    | --mbr : use mbr partitioning table - default "gpt"
-gpt    | --gpt : use gpt partitioning table - default "gpt"
-swap   | --swapsize <int>G|M|K|B : set swap partition size  
-boot   | --bootsize <int>G|M|K|B : set boot partition size 
-layout | --layout <basic|advanced> : set partition layout (splitted home or all in /)

** packages **
-bundle | --package-bundle <minimal|gurgui|devel> : bundle of tools to install - default 'gurgui'
-extra  | --extra-packages <csv> : packages to install

** graphics **
-graphics | --graphics : install and enable graphics - default false
EOF
}

#    + Graphical environment setup
function setupGraphicalEnvironment(){
  if [[ -z "$graphicalEnvironment" || -z "$displayManager" ]]; then
    read -r -p "[?] Do you want to install a graphical environment? y/n " ans
  
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
      printf "[!] Choice must be between 0 and %i\n" "$((n-1))"
      exit 1
    fi
    
    n=0
    
    # Assign user choice to the variable
    for i in "${!graphEnv[@]}"; do
      if (( $n == ans )); then
        graphicalEnvironment="$(echo ${graphEnv[$i]} | cut -d ' ' -f 1)"
        displayManager="$(echo ${graphEnv[$i]} | cut -d ' ' -f 2)"
      fi
      (( ++n ))
    done
  fi
} 
#    - Graphical environment setup

#    + Disk functions
function fdiskCommandGPT(){
 fdiskcmd+="g\\n" # Create GPT disklabel
 fdiskcmd+="n\\n\\n\\n+""$BOOTSIZE""K\\nt\\nuefi\\n"     # Create boot partition
 fdiskcmd+="n\\n\\n\\n+""$SWAPSIZE""K\\nt\\n2\\nswap\\n" # Create swap partition

 if [ "${partitionLayout,,}" == "basic" ]; then
  fdiskcmd+="n\\n\\n\\n\\nt\\n3\\nlinux\\n" # Root partition
 elif [ "${partitionLayout,,}" == "advanced" ]; then
  fdiskcmd+="n\\n\\n\\n+""$rootsize""K\\nt\\n3\\n23\\n" # Root partition - Type code 23 = linux root (x86-64)
  fdiskcmd+="n\\n\\n\\n\\nt\\n4\\nlinux\\n"     # Home partition - Type code 42 = linux home
 else
  printf "[!] Invalid partition layout: '%s'\n" "$partitionLayout" && exit 1
 fi

}

function fdiskCommandMBR(){
  fdiskcmd="o\\n" # Create DOS (MBR) disklabel
  fdiskcmd+="n\\n\\n\\n\\n+""$BOOTSIZE""K\\nt\\nlinux\\na\\n" # Create boot partition and mark as bootable
  fdiskcmd+="n\\n\\n\\n\\n+""$SWAPSIZE""K\\nt\\n2\\nswap\\n"  # Create swap partition

  if [ "${partitionLayout,,}" == "basic" ]; then
    fdiskcmd+="n\\n\\n\\n\\n\\nt\\n3\\nlinux\\n"
  elif [ "${partitionLayout,,}" == "advanced" ]; then
    fdiskcmd+="n\\n\\n\\n\\n+""$rootsize""K\\nt\\n3\\nlinux\\n"
    fdiskcmd+="n\\np\\n\\n\\nt\\n4\\nlinux\\n"
  else
    printf "[!] Invalid partition layout: '%s'\n" "$partitionLayout" && exit 1
  fi
}

function getTargetDisk(){
  local availableDisks=($(lsblk -dn -o PATH,SIZE | grep -v "0B\|loop\|ram\|sr" | awk '{print $1}'))
  n=0

  printf -- "-- Looking for disks in the system...\n"
  
  for disk in ${availableDisks[@]}; do
    printf "    %i: %s\n" "$n" "$(lsblk -o PATH,MODEL,SIZE -dn $disk)" 
    ((++n))  
  done
  
  while true; do
    read -p "-- Choice: " ans
    if [[ $ans =~ ^[0-9]$ ]] && (( ans < ${#availableDisks[@]} && ans >= 0 )); then
      DISK=${availableDisks[ans]}  
      break
    else
      continue
    fi
  done

  [ -z "$DISK" ] && exit 1
}

function setupDisk(){

  if [[ -z "$DISK" ]]; then
    getTargetDisk
  fi

  DISK_SIZE=$(( $(lsblk -o SIZE -bdn "$DISK") / 1024 ))
  AVAILABLE="$DISK_SIZE"

  for kilobytes in $BOOTSIZE $SWAPSIZE; do
    (( AVAILABLE -= "$kilobytes" ))
  done
  
  if [ "${partitionLayout}" == "advanced" ]; then
    ROOTSIZE=$(( AVAILABLE / 100 * 40 )) # root:40% home:60%
    HOMESIZE=$(( AVAILABLE - ROOTSIZE ))
  else
    ROOTSIZE="$AVAILABLE"
  fi

  # Check if target disk is mounted
  if mount | grep -q "$DISK"; then 
    printf -- "-- Target disk - '%s' - is mounted, umounting..." "$DISK"
    umount -A "$DISK" &>/dev/null || printf -- "-- Couldn't umount, exiting..." && exit 1
  fi
  
  case "${partitionScheme,,}" in
    gpt)
      fdiskCommandGPT
      ;;
    mbr)
      fdiskCommandMBR
      ;;
    *)
      printf "[!] Detected wrong partitioning scheme '%s'\n" "${partitionScheme,,}" && exit 1
      ;;
  esac

  fdiskcmd+="w\\n"
  
  # TODO - print mountpoints information + partitions
  local boot="$DISK"p1
  local swap="$DISK"p2
  local root="$DISK"p3
  local home="$DISK"p4

# TODO - Change table: PARTITION MOUNTPOINT SIZE
  cat << EOF
      == Disk layout ==
TYPE          PATH            SIZE
boot        $boot     $(( BOOTSIZE / 1024 )) mb
swap        $swap     $(( SWAPSIZE / 1024 )) mb
root        $root     $(( ROOTSIZE / 1024 )) mb
EOF

(( $HOMESIZE > 0 )) && printf "home        %s     %s mb\n" "$home" "$(( HOMESIZE / 1024))"

  # Ask for confirmation since disk wiping / partition erasing will be made
  read -r -p "-- WARNING - This will erase signatures from existing disk and delete partitions, continue? y/n: " ans
  if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then 
    exit 0 
  fi
  
  # Wipe existing signatures and partition table entries
  sfdisk --delete "$DISK"
  wipefs --force --all "$DISK"
  partprobe "$DISK"

  # Partition the disk
  echo -e "$fdiskcmd" | fdisk -w always -W always "$DISK" &>/dev/null

  partprobe

  # Create root and swap filesystems since they will be the same for both mbr | gpt 
  mkfs.ext4 "$root" || printf "[!] failed creating ext4 fs on root partition '%s'\n" "$root" && exit 1
  mkswap "$swap"    || printf "[!] failed creating swap fs on swap partition '%s'\n" "$swap" && exit 1

  # Mount the disk
  if [ "${partitionScheme,,}" == "mbr" ]; then
    # Create appropiate boot fs
    mkfs.ext2 "$boot" || printf "[!] failed creating ext2 fs on boot partition '%s'\n" "$boot" && exit 1
    
    mount "$root" "$mountpoint"
    mkdir -p "$mountpoint/boot"
    mount "$boot" "$mountpoint/boot"    

    if [ "${partitionLayout}" == "advanced" ]; then
      mkfs.ext4 "$home" || printf "[!] failed creating ext4 fs on home partition '%s'\n" "$home" && exit 1

      mkdir -p "$mountpoint/home" 
      mount "$home" "$mountpoint/home"
    fi
  elif [ "${partitionScheme,,}" == "gpt" ]; then
    # Create appropiate boot fs
    mkfs.vfat -F32 "$boot" || printf "[!] failed creating FAT32 fs on boot partition '%s'\n" "$boot" && exit 1

    mount "$root" "$mountpoint"
    mkdir -p "$mountpoint/boot/efi"
    mount "$boot" "$mountpoint/boot/efi"

    if [ "${partitionLayout,,}" == "advanced" ]; then
      mkfs.ext4 "$home" || printf "[!] failed creating ext4 fs on home partition '%s'\n" "$home" && exit 1

      mkdir -p "$mountpoint/home"
      mount "$home" "$mountpoint/home"
    fi
  fi

  # Enable swap
  swapon "$swap"
} 
#    - Disk functions

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
  elif [[ "$opt" == "-disk" || "$opt" == "--disk" ]]; then
    DISK="${args[++i]}"
  elif [[ "$opt" == "-u" || "$opt" == "--user" ]]; then
    user="${args[++i]}"
  elif [[ "$opt" == "-p" || "$opt" == "--pass" ]]; then
    pass="${args[++i]}"
  elif [[ "$opt" == "-h" || "$opt" == "--hostname" ]]; then
    hostname="${args[++i]}"
  elif [[ "$opt" == "-mbr" || "$opt" == "--mbr" ]]; then
    partitionScheme="mbr"
  elif [[ "$opt" == "-gpt" || "$opt" == "--gpt" ]]; then
    partitionScheme="gpt"
  elif [[ "$opt" == "-extra" || "$opt" == "--extra-packages" ]]; then
    packagesToInstall+=$(echo "${args[++i]}" | tr ',' ' ')
    (( ++i ))
  elif [[ "$opt" == "-bundle" || "$opt" == "--package-bundle" ]]; then
    packagesToInstall+=$(packageBundle["${args[++i]}"])
    (( ++i ))
  elif [[ "$opt" == "-graphics" || "$opt" == "--graphics" ]]; then
    enableGraphics=true
  elif [[ "$opt" == "-mnt" || "$opt" == "--mountpoint" ]]; then
    mountpoint="${args[++i]}"
    if [ ! -e "$mountpoint" ]; then
      printf "mountpoint '%s' doesn't exist\n" "$mountpoint" && exit 1
    fi
    if mount | grep -q "$mountpoint"; then
      umount "$mountpoint" || printf "can't umount" && exit 1
    fi
  elif [[ "$opt" == "-swap" || "$opt" == "--swapsize" ]]; then
    SWAPSIZE=$(__retrieve_size "${args[++i]}")
    (( $SWAPSIZE <= 0 )) &>/dev/null && printf "[!] ignoring invalid given swap size '%s'\n " "${args[++i]}" && exit 1
    (( ++i ))
  elif [[ "$opt" == "-boot" || "$opt" == "--bootsize" ]]; then
    BOOTSIZE=$(__retrieve_size "${args[++i]}")
    (( $BOOTSIZE <= 0 )) &>/dev/null && printf "[!] ignoring invalid given boot size '%s'\n" "${args[++i]}" && exit 1 
    (( ++i ))
  elif [[ "$opt" == "-layout" || "$opt" == "--layout" ]]; then
    partitionLayout="${args[++i]}"
  else 
    printf "[-] Unknown option '%s'\n" "$opt"
  fi
 done
}

function setupArch(){
  # Install packages
  pacstrap -K /mnt "$packagesToInstall"
  # Extra stuff 
  if (( ${#basic_extra} > 0 )); then
    echo "basic extra is not empty: $basic_extra"
    pacstrap /mnt $basic_extra
  else 
    echo "basic extra is empty: $basic_extra"
  fi
  
  # GRAPHICAL ENVIRONMENT
  source graphicalenvs.sh
  
  # - Generate new system's fstab
  genfstab -U /mnt > /mnt/etc/fstab
  
  # - Do some configuration in the new system

  cat << EOF > /mnt/root/garch_autoinstall.sh 
#!/bin/bash 
# Gurgui's arch auto-install script

# Upgrade system 
pacman -Syuu --noconfirm

# Create sudoer
useradd -m "$user"

$(if [ -z "$password" ]; then read -p -s "sudoer password: " pass; echo "pass=$pass"; fi)
echo -e "$pass\n$pass" | passwd "$user" 
echo -e "# Gurgui automated script\n"$user" ALL=(ALL : ALL) ALL" >> /etc/sudoers

# Set hostname
echo "$hostname" > /etc/hostname 

# Set keyboard layout
echo "$keyboard_layout" > /etc/vconsole.conf

# Enable services 
systemctl enable -y NetworkManager 
$(enableGraphics && printf "systemctl enable -y %s" "$displayManager")

# Install the bootloader
grub-install "$DISK"

# Update grub config file for further boots
grub-mkconfig -o /boot/grub/grub.cfg 
EOF

  # Give 'garch_autoinstall.sh' script execute permissions and execute it
  arch-chroot /mnt /bin/bash -c 'chmod +x /root/garch_autoinstall.sh'
  arch-chroot /mnt /bin/bash -c '/root/garch_autoinstall.sh'
  
  # Delete it after being used
  rm /mnt/root/garch_autoinstall.sh
  
  read -r -p "Installation done, reboot is required to enjoy the new system, umount and reboot now? y/n " res
  
  if [[ ${res,,} == "y" || ${res,,} == "yes" ]]
  then
    umount -a
    swapoff "$DISK"2
    reboot
  fi
}

function main(){
  # Parse arguments (override, checks etc.)
  parse
  
  # Get target disk interactively and set DISK | DISK_SIZE variables
  setupDisk

  # Set desired graphical environment if --graphics was given
  $enableGraphics && setupGraphicalEnvironment

  setupArch

  # Do stuff
  loadkeys "$keyboard_layout"
}

# - Functions

main
exit 1