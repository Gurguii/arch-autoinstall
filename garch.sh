#!/bin/bash 
# Function to check the status code of every command to avoid weird
# results and improve 'debuggability'?

# ACTUALLY UNUSED - I DON'T KNOW HOW TO PASS A COMMAND TO THIS :))
function check(){
  if (( $debug )); then
    bash -c "$1" | tee -a "$debugfile"
  else 
    bash -c "$1" &>/dev/null 
  fi
  if [[ $? -ne 0 ]]; then
    printf "[!] Command '%s' failed, exiting ...\n" "$1"
  fi
}

# Make sure the configuration file is in the current directory, and if so, import it
if [[ -e "garch.conf" ]]; then 
  source "garch.conf"
else
  printf "[!] Can't find config file\nplease make sure the 'garch.conf' file is in the current directory:'%s'\n" "$(pwd)"
  exit 1
fi 

# - Load keyboard layout
loadkeys "$keyboard_layout"

# DISK CONFIGURATION
# 'disk.sh' performs everything related to disks
source disk.sh

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
