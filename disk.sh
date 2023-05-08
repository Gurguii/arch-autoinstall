#!/bin/bash

function get_target_disk(){
  available_disks=($(lsblk -dn -o NAME | grep -v "loop\|ram\|sr"))
  n=0
  
  printf "[+] Looking for disks in the system...\n"
  
  for disk in ${available_disks[@]}; do
      printf "%i: %s - size %s\n" "$n" "/dev/$disk" "$(lsblk -o SIZE /dev/$disk | grep -v 'SIZE' | head -1)" 
      ((++n))  
  done
  
  while true; do
    read -p "[?] Which disk to use? " ans
    if [[ $ans =~ ^[0-9]$ ]] && (( ans < ${#available_disks[@]} && ans >= 0 )); then
      disk=${available_disks[ans]}  
      break
    else
      continue
    fi
  done
  printf "Chosen disk %s\n" "/dev/$disk"
  disk="/dev/$disk"
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
  umount "$disk*"
  swaptest=$(swapon | grep "$disk" | cut -d' ' -f1)
  if ! [[ -z $swaptest ]]; then
    swapoff "$swaptest"
  fi
fi

# Ask for confirmation since disk wiping / partition erasing will be made
read -r -p "This will erase signatures from existing disk and delete partitions, continue? " ans
if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then 
  exit 0 
fi


# Delete existing partitions 
# echo -e "d\n1\nd\n2\nd\nw" | fdisk "$disk"

# Wipe existing signatures and partition table entries
wipefs --force --all "$disk"
partprobe "$disk"

# 
if [[ "${partitionScheme,,}" == "gpt" ]]; then 
  echo -e "g\nn\n\n\n+1G\nt\n1\n83\nn\n\n\n+4G\nn\n\n\n\nw\n" | fdisk -c -n "$disk"
elif [[ "${partitionScheme,,}" == "mbr" ]]; then 
  echo -e "o\nn\n\n\n+1G\nt\n1\n83\nn\n\n\n+4G\nn\n\n\n\nw\n" | fdisk -c=dos -n "$disk"
fi
# - Create disk partitions B4G S4M R3G - 4 gigabytes boot, 4 megabytes swap, 3 gigabytes root (an idea for custom layouts)
## First partition (boot)
#echo -e "n\np\n1\n\n+1G\nw" | fdisk "$disk"
## Second partition (swap)
#echo -e "n\np\n2\n\n+8G\nw" | fdisk "$disk"
## Third partition (rootfs)
#echo -e "n\np\n3\n\n\nw" | fdisk "$disk"

partprobe "$disk"

# - Format disk partitions 
# Boot partition 
mkfs.vfat -F 32 "$disk"1
# Rootfs partition
mkfs.ext4 "$disk"2
# Swap partition
mkswap "$disk"3

# - Mount partitioned disk
mount "$disk"3 /mnt
mkdir -p /mnt/boot/efi
mount "$disk"1 /mnt/boot/efi 
swapon "$disk"2
