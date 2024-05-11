#!/bin/bash 

# + Variables

argc=$#
args=($@)

verbose=false

keyboard_layout="es"
timezone="UTC+0"

mountpoint="/mnt"

fdiskcmd=""


# + New system
DISK=""
DISK_SIZE=0
partitionScheme="gpt"
partitionLayout="basic" # basic|advanced
partitionBootSize="1048576" # 1G - sizes are in Kb
partitionSwapSize="8388608" # 8G - sizes are in Kb

hostname="arch1to"

user="admin"
pass=""

enableGraphics=false
graphicalEnvironment="lxqt"
displayManager="sddm"

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
# note: -> | linux base linux-firmware linux-headers grub efibootmgr networkmanager | <- packages will always be installed
packageBundle['minimal']=""
packageBundle['gurgui']="base-devel net-tools nmap neovim ttf-firacode-nerd nodejs zip unzip p7zip wireshark-qt john hashcat subbrute sudo"
packageBundle['devel']="base-devel perl ruby nodejs"

packagesToInstall='base-devel net-tools nmap neovim ttf-firacode-nerd nodejs zip unzip p7zip wireshark-qt john hashcat'

extraPackages=""
# - Variables

# + Functions
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
function gptDisk(){
 local available="$DISK_SIZE"

 echo "before: $available"
 for kb in $partitionBootSize $partitionSwapSize; do
  (( available -= "$kb" ))
 done
 echo "after: $available"
 fdiskcmd+="g\\n"; # Create GPT disklabel
 fdiskcmd+="n\\n\\n\\n+$partitionBootSize""K\\nt\\nuefi\\n" # Create boot partition
 fdiskcmd+="n\\n\\n\\n+$partitionSwapSize""K\\nt\\n2\\nswap\\n" # Create swap partition
 
 if [ "$partitionLayout" == "basic" ]; then
  fdiskcmd+="n\\n\\n\\n\\nt\\n3\\nlinux\\n" # Root partition
 elif [ "$partitionLayout" == "advanced" ]; then
  local rootsize=$(( available / 100 * 40 ))  # root:40% home:60%
  echo "$rootsize"
  fdiskcmd+="n\\n\\n\\n+$rootsize""K\\nt\\n3\\n23\\n" # Root partition - Type code 23 = linux root (x86-64)
  fdiskcmd+="n\\n\\n\\n\\nt\\n4\\nlinux\\n"     # Home partition - Type code 42 = linux home
 else
  printf "[!] invalid partition layout: '%s'\n" "$partitionLayout" && exit 1
 fi

}

function mbrDisk(){
 echo "mbrDisk()"
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

  if [ -z "$DISK" ]; then
    exit 1
  fi
}

function setupDisk(){
  if [[ -z "$DISK" ]]; then
    getTargetDisk
  fi

  DISK_SIZE=$(( $(lsblk -o SIZE -bdn "$DISK") / 1024 ))

  # Check if target disk is mounted
  if mount | grep -q "$DISK"; then 
    printf -- "-- Target disk - '%s' - is mounted, umounting..." "$DISK"
    umount -A "$DISK" &>/dev/null || printf -- "-- Couldn't umount, exiting..." && exit 1
  fi
  
  case "${partitionScheme,,}" in
    gpt)
      gptDisk
      ;;
    mbr)
      mbrDisk
      ;;
    *)
      printf "[!] Detected wrong partitioning scheme '%s'\n" "${partitionScheme,,}"
      exit 1
      ;;
  esac

  fdiskcmd+="w\\n"
  
  echo "fdisk command: $fdiskcmd"

  # Ask for confirmation since disk wiping / partition erasing will be made
  read -r -p "-- WARNING - This will erase signatures from existing disk and delete partitions, continue? y/n: " ans
  if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then 
    exit 0 
  fi
  
  # Wipe existing signatures and partition table entries
  sfdisk --delete "$DISK"
  wipefs --force --all "$DISK"
  partprobe "$DISK"

  exit 1
}
#    - Disk functions

function __retrieve_size(){
  # $1 - user input, e.g 5G, 4M, 3K, 2B
  size="${1:0: -1}"
  unit="${1: -1}"

  case "${unit,,}" in
    g ) printf -- "%i" "$(( $size * 1024 * 1024 ))" ;;
    m ) printf -- "%i" "$(( $size * 1024  ))" ;;
    k ) printf -- "%i" "$size" ;;
    b ) printf -- "%i" "$(( $size / 1024 ))" ;;
    * ) printf -- "-1"
  esac
}

function parse(){
 for (( i = 0 ; i < $argc ; ++i )); do
  opt="${args[i],,}"
  if [[ "$opt" == "-d" || "$opt" == "--debug" ]]; then
    debug=true
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
    partitionSwapSize=$(__retrieve_size "${args[++i]}")
    (( $partitionSwapSize <= 0 )) &>/dev/null && printf "[!] ignoring invalid given swap size '%s'\n " "${args[++i]}" && exit 1
    (( ++i ))
  elif [[ "$opt" == "-boot" || "$opt" == "--bootsize" ]]; then
    partitionBootSize=$(__retrieve_size "${args[++i]}")
    (( $partitionBootSize <= 0 )) &>/dev/null && printf "[!] ignoring invalid given boot size '%s'\n" "${args[++i]}" && exit 1 
    (( ++i ))
  elif [[ "$opt" == "-layout" || "$opt" == "--layout" ]]; then
    partitionLayout="${args[++i]}"
  else 
    printf "[-] Unknown option '%s'\n" "$opt"
  fi
 done
}

function main(){
  # Parse arguments (override, checks etc.)
  parse
  
  # Get target disk interactively and set DISK | DISK_SIZE variables
  setupDisk

  # Set desired graphical environment if --graphics was given
  enableGraphics && setupGraphicalEnvironment

  # Do stuff
  loadkeys "$keyboard_layout"
}

# - Functions

main
exit 1

# - Install stuff in the new system

# Essential stuff for the system to work (think about having networkmanager as default)

pacstrap -K /mnt "$packagesToInstall"
#pacstrap -K /mnt base linux linux-firmware grub efibootmgr networkmanager sudo

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

# Generate a random 16 character pseudorandom root password
newpasswd=\$(head /dev/urandom | tr -dc A-Za-z0-9\!\@\#\$\%\^\&\*\(\)_\+\-\=\{\}\[\]\|\:\\\;\"\'\,\.\?\/ | head -c 16) 
echo -e "\$newpasswd\n\$newpasswd" | passwd 
newpasswd=""

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
systemctl enable -y "$displayManager"

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