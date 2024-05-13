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
packageBundle['devel']="dotnet base-devel perl ruby nodejs"

# + New system vars
mountpoint="/mnt"
fdiskcmd=""

DISK=""
DISK_SIZE=0
AVAILABLE=0

BOOT_SIZE=1048576 # 1GB
SWAP_SIZE=8388608 # 8GB
ROOT_SIZE=0
HOME_SIZE=0

BOOT_PATH=""
SWAP_PATH=""
ROOT_PATH=""
HOME_PATH=""

grubBoot=""

partitionScheme="gpt"
partitionLayout="basic" # basic|advanced

hostname="arch1to"

user="admin"
pass=""

enableGraphics=false
graphicalEnvironment=""
displayManager=""

packagesToInstall='linux base linux-firmware linux-headers grub networkmanager efibootmgr sudo'
#  - New System vars

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
      printf "[-] Choice must be between 0 and %i\n" "$((n-1))"
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
 fdiskcmd+="n\\n\\n\\n+""$BOOT_SIZE""K\\nt\\nuefi\\n"     # Create boot partition
 fdiskcmd+="n\\n\\n\\n+""$SWAP_SIZE""K\\nt\\n2\\nswap\\n" # Create swap partition

 if [ "${partitionLayout,,}" == "basic" ]; then
  fdiskcmd+="n\\n\\n\\n\\nt\\n3\\nlinux\\n" # Root partition
 elif [ "${partitionLayout,,}" == "advanced" ]; then
  fdiskcmd+="n\\n\\n\\n+""$ROOT_SIZE""K\\nt\\n3\\n23\\n" # Root partition - Type code 23 = linux root (x86-64)
  fdiskcmd+="n\\n\\n\\n\\nt\\n4\\nlinux\\n"     # Home partition - Type code 42 = linux home
 fi

}

function fdiskCommandMBR(){
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

function getTargetDisk(){
  local availableDisks=($(lsblk -dn -o PATH,SIZE | grep -v "0B\|loop\|ram\|sr" | awk '{print $1}'))
  n=0

  printf -- "-- Looking for disks in the system...\n\n"
  
  for disk in ${availableDisks[@]}; do
    printf "    %i: %s\n" "$n" "$(lsblk -o PATH,MODEL,SIZE -dn $disk)" 
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

  [ -z "$DISK" ] && exit 1
}

function setupDisk(){

  if [[ -z "$DISK" ]]; then
    getTargetDisk
  fi

  BOOT_PATH="$DISK"p1
  SWAP_PATH="$DISK"p2
  ROOT_PATH="$DISK"p3

  DISK_SIZE=$(( $(lsblk -o SIZE -bdn "$DISK") / 1024 ))
  AVAILABLE="$DISK_SIZE"

  for kilobytes in $BOOT_SIZE $SWAP_SIZE; do
    (( AVAILABLE -= "$kilobytes" ))
  done
  
  (( $AVAILABLE <= 0 )) && printf "[-] Not enough memory %lu kb for boot and %lu kb for swap\n[-] Aborting...\n" "$BOOT_SIZE" "$SWAP_SIZE" && exit 1 
  
  if [ "${partitionLayout}" == "advanced" ]; then
    ROOT_SIZE=$(( AVAILABLE / 100 * 40 )) # root:40% home:60%
    HOME_SIZE=$(( AVAILABLE - ROOT_SIZE ))
    HOME_PATH="$DISK"p4
  else
    ROOT_SIZE="$AVAILABLE"
  fi

  # Check if target disk is mounted
  if mount | grep -q "$DISK"; then 
    printf -- "-- Target disk - '%s' - is mounted, umounting...\n" "$DISK"
    umount $(mount | grep "$DISK" | awk '{print $1}')
    mount | grep -q "$DISK" && printf -- "-- Couldn't umount, exiting...\n" && exit 1
  fi
  
  case "${partitionScheme,,}" in
    gpt)
      fdiskCommandGPT
      ;;
    mbr)
      fdiskCommandMBR
      ;;
    *)
      printf "[-] Detected wrong partitioning scheme '%s'\n" "${partitionScheme,,}" && exit 1
      ;;
  esac

  fdiskcmd+="w\\n"
  
  # Show the disk layout to be applied
  cat << EOF

    PART          PATH            SIZE
    boot          $BOOT_PATH     $(( BOOT_SIZE )) Kb
    swap          $SWAP_PATH     $(( SWAP_SIZE )) Kb
    root          $ROOT_PATH     $(( ROOT_SIZE )) Kb
EOF

  (( $HOME_SIZE > 0 )) && printf "    home          %s     %s Kb\n" "$HOME_PATH" "$HOME_SIZE"

  # Ask for confirmation since disk wiping / partition erasing will be made
  printf "\n"
  read -r -p "-- WARNING - This will erase signatures from existing disk and delete partitions, continue? y/n: " ans
  if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then 
    exit 0 
  fi
  
  # Wipe existing signatures and partition table entries
  sfdisk --delete "$DISK"
  wipefs --force --all "$DISK"

  # Partition the disk
  echo -e "$fdiskcmd" | fdisk -w always -W always "$DISK" &>/dev/null

  partprobe

  # Create root and swap filesystems since they will be the same for both mbr | gpt 
  mkfs.ext4 "$ROOT_PATH" #|| printf "[-] failed creating ext4 fs on root partition '%s'\n" "$ROOT_PATH" && exit 1
  mkswap "$SWAP_PATH"    #|| printf "[-] failed creating swap fs on swap partition '%s'\n" "$SWAP_PATH" && exit 1


  # Mount the disk
  if [ "${partitionScheme,,}" == "mbr" ]; then
    # Create appropiate boot fs
    mkfs.ext2 "$BOOT_PATH" #|| printf "[-] failed creating ext2 fs on boot partition '%s'\n" "$BOOT_PATH" && exit 1
    
    mount "$ROOT_PATH" "$mountpoint"
    mkdir -p "$mountpoint/boot"
    mount "$BOOT_PATH" "$mountpoint/boot"    

    if [ "${partitionLayout}" == "advanced" ]; then
      mkfs.ext4 "$HOME_PATH" #|| printf "[-] failed creating ext4 fs on home partition '%s'\n" "$HOME_PATH" && exit 1

      mkdir -p "$mountpoint/home" 
      mount "$HOME_PATH" "$mountpoint/home"
    fi
  elif [ "${partitionScheme,,}" == "gpt" ]; then
    # Create appropiate boot fs
    mkfs.vfat -F32 "$BOOT_PATH" #|| printf "[-] failed creating FAT32 fs on boot partition '%s'\n" "$BOOT_PATH" && exit 1

    mount "$ROOT_PATH" "$mountpoint"
    mkdir -p "$mountpoint/boot/efi"
    mount "$BOOT_PATH" "$mountpoint/boot/efi"

    if [ "${partitionLayout,,}" == "advanced" ]; then
      mkfs.ext4 "$HOME_PATH" #|| printf "[-] failed creating ext4 fs on home partition '%s'\n" "$HOME_PATH" && exit 1

      mkdir -p "$mountpoint/home"
      mount "$HOME_PATH" "$mountpoint/home"
    fi
  fi

  # Enable swap
  swapon "$SWAP_PATH"

  # Print disk layout after being partitioned
  fdisk -o device,size,type -k "$DISK" | grep -E "^(/|Disk $DISK)"
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
    packagesToInstall+=" $(echo "${args[++i]}" | tr ',' ' ')"
  elif [[ "$opt" == "-bundle" || "$opt" == "--package-bundle" ]]; then
    packagesToInstall+=" ${packageBundle["${args[++i]}"]}"
  elif [[ "$opt" == "-graphics" || "$opt" == "--graphics" ]]; then
    enableGraphics=true
  elif [[ "$opt" == "-mnt" || "$opt" == "--mountpoint" ]]; then
    mountpoint="${args[++i]}"
    if [ ! -e "$mountpoint" ]; then
      printf "[-] mountpoint '%s' doesn't exist\n" "$mountpoint" && exit 1
    fi
    if mount | grep -q "$mountpoint"; then
      umount "$mountpoint" || printf "can't umount" && exit 1
    fi
  elif [[ "$opt" == "-swap" || "$opt" == "--swapsize" ]]; then
    SWAP_SIZE=$(__retrieve_size "${args[++i]}")
    (( $SWAP_SIZE <= 0 )) &>/dev/null && printf "[-] ignoring invalid given swap size '%s'\n " "${args[++i]}" && exit 1
    (( ++i ))
  elif [[ "$opt" == "-boot" || "$opt" == "--bootsize" ]]; then
    BOOT_SIZE=$(__retrieve_size "${args[++i]}")
    (( $BOOT_SIZE <= 0 )) &>/dev/null && printf "[-] ignoring invalid given boot size '%s'\n" "${args[++i]}" && exit 1 
    (( ++i ))
  elif [[ "$opt" == "-layout" || "$opt" == "--layout" ]]; then
    partitionLayout="${args[++i]}"
    case "${partitionLayout,,}" in
      basic | advanced ) ;;
      * ) printf "[-] Invalid partition layout\nbasic: / boot swap (3 parts)\nadvanced: / /home boot swap (4 parts)\n" && exit 0
    esac
  else 
    printf "[-] Unknown option '%s'\n" "$opt"
  fi
 done
}

function setupArch(){
  # Install packages
  pacstrap -K "$mountpoint" "$packagesToInstall"

  # Extra stuff 
  if (( ${#basic_extra} > 0 )); then
    echo "basic extra is not empty: $basic_extra"
    pacstrap "$mountpoint" $basic_extra
  else 
    echo "basic extra is empty: $basic_extra"
  fi
  
  # GRAPHICAL ENVIRONMENT
  source graphicalenvs.sh
  
  # - Generate new system's fstab
  genfstab -U "$mountpoint" > "$mountpoint"/etc/fstab
  
  # - Do some configuration in the new system

  cat << EOF > "$mountpoint/root/garch_autoinstall.sh" 
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
  arch-chroot "$mountpoint" /bin/bash -c 'chmod +x /root/garch_autoinstall.sh'
  arch-chroot "$mountpoint" /bin/bash -c '/root/garch_autoinstall.sh'
  
  # Delete it after being used
  rm "$mountpoint/root/garch_autoinstall.sh"
  
  umount -a
  swapoff "$SWAP_PATH"

  read -r -p "[+] Installation done, reboot now? y/n " res
  
  if [[ ${res,,} == "y" || ${res,,} == "yes" ]]; then
    reboot
  fi
}

function main(){
  # Parse arguments (override, checks etc.)
  parse
  
  setupArch
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