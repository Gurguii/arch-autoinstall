#!/bin/bash

function get_target_disk(){
  available_disks=$(lsblk -dn -o NAME | grep -v "loop\|ram\|sr")
  empty_disks=()
  n=0
  
  printf "[+] Looking for empty disks in the system...\n"
  
  for disk in ${available_disks[@]}; do
    if [[ -z $(sfdisk -d /dev/$disk 2>/dev/null) ]]; then
      printf "%i: %s - size %s\n" "$n" "/dev/$disk" "$(lsblk -o SIZE /dev/$disk | grep -v 'SIZE')" 
      empty_disks+=("$disk")
      (( ++n ))
    fi
  done
  
  while true; do
    read -p "[?] Which disk to use? " ans
    if [[ $ans =~ ^[0-9]$ ]] && (( ans < ${#empty_disks[@]} && ans >= 0 )); then
      disk=${empty_disks[ans]}  
      break
    else
      continue
    fi
  done
  printf "Chosen disk %s\n" "/dev/$disk"
}

if [[ -z "$disk" ]]; then
  get_target_disk
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
