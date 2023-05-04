#!/bin/bash 
# Function to check the status code of every command to avoid weird
# results and improve 'debuggability'?

# ACTUALLY UNUSED - I DON'T KNOW HOW TO PASS A COMMAND TO THIS :))
function check(){
  # If debug mode is enabled (disabled by default) errors will be printed, else errors and output will be 
  if [ "$debug" ]; then 
    "$1" 1>> stdout.logs 2>> stderr.logs 
  else 
    "$1" &>/dev/null
  fi
  # Check status code to see if the command failed and exiting is required
  if [ "$?" -ne 0 ]; then 
    echo -e "command "$1" failed\n"
    exit 1 
  fi
}
# Make sure the configuration file is in the current directory, and if so, import it
if [[ -e "garch.conf" ]]; then 
  source "garch.conf"
else
  echo -e "can't find config file, please make sure the 'garch.conf' file is in the current directory: "$(pwd)"\n"
  exit 1
fi 

# Check if target disk is already mounted
if mount | grep -q "$disk"; then 
  read -r -p "Target disk -"$disk"- is already mounted, umount and proceed? y/n " ans
  if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then
    exit 0 
  fi
  umount -a
  swapoff "$swap"
fi

# Ask for confirmation since disk wiping / partition erasing will be made
read -r -p "This will erase signatures from existing disk and delete partitions, continue? " ans
if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then 
  exit 0 
fi

# - Load keyboard layout
loadkeys "$keyboard_layout"

# Delete existing partitions 
echo -e "d\n1\nd\n2\nd\nw" | fdisk "$disk"

# Wipe existing signatures and partition table entries
wipefs --force --all "$disk"
partprobe "$disk"

# - Create disk partitions
# First partition (boot)
echo -e "n\np\n1\n\n+1G\nw" | fdisk "$disk"
# Second partition (swap)
echo -e "n\np\n2\n\n+8G\nw" | fdisk "$disk"
# Third partition (rootfs)
echo -e "n\np\n3\n\n\nw" | fdisk "$disk"

# - Format disk partitions 
# Boot partition 
mkfs.vfat -F 32 "$boot"
# Rootfs partition
mkfs.ext4 "$rootfs"
# Swap partition
mkswap "$swap"

# - Mount partitioned disk
mount "$rootfs" /mnt
mkdir -p /mnt/boot/efi
mount "$boot" /mnt/boot/efi 
swapon "$swap"

# - Install stuff in the new system

# Essential stuff for the system to work (think about having networkmanager as default)

pacstrap /mnt base linux linux-firmware grub efibootmgr networkmanager sudo

# Extra stuff 
if (( ${#basic_extra} > 0 )); then
  echo "basic extra is not empty: $basic_extra"
  sleep 10
  pacstrap /mnt "$basic_extra"
else 
  echo "basic extra is empty: $basic_extra"
fi
sleep 10
# - Generate fstab

genfstab -U /mnt > /mnt/etc/fstab

# - Do some configuration in the new system

cat << EOF > /mnt/root/garch_autoinstall.sh 
#!/bin/bash 
# Gurgui auto-install script

# Upgrade system 
pacman -Syu

# Generate a random 16 character pseudorandom root password
newpasswd=\$(head /dev/urandom | tr -dc A-Za-z0-9\!\@\#\$\%\^\&\*\(\)_\+\-\=\{\}\[\]\|\:\\\;\"\'\,\.\?\/ | head -c 16) 
echo -e "\$newpasswd\n\$newpasswd" | passwd 

# Create sudoer
useradd -m "$user"
echo -e "$pass\n$pass" | passwd "$user" 
echo -e "# Gurgui automated script\n"$user" ALL=(ALL : ALL) ALL" >> /etc/sudoers
# Set hostname
echo "$hostname" > /etc/hostname 

# Set keyboard layout
echo "$keyboard_layout" > /etc/vconsole.conf

# Enable services 
systemctl enable -y NetworkManager 
systemctl enable -y gdm

# Install the bootloader
grub-install "$disk"

# Update grub config file for further boots
grub-mkconfig -o /boot/grub/grub.cfg 
EOF

arch-chroot /mnt /bin/bash -c 'chmod +x /root/garch_autoinstall.sh'

# - exit, umount and hopefully enjoy our new system 
arch-chroot /mnt /bin/bash -c 'bash /root/garch_autoinstall.sh'
rm /mnt/root/garch_autoinstall.sh

read -r -p "Installation done, reboot is required to enjoy the new system, umount and reboot now? y/n " res
if [[ ${res,,} == "y" || ${res,,} == "yes" ]]
then
  umount -a
  reboot
fi
