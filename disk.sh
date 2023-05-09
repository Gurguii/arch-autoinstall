#!/bin/bash
function gptDisk(){
  for i in ${!diskLayout[@]}; do
  	type="${diskLayout[i]:0:4}"
  	size="${diskLayout[i]:4}"
    printf "iterating through %s\n" "${diskLayout[i]}"
  	sleep 3
    case "${type,,}" in
  		boot)
        bootPartition="$disk""$((i++))"
        if [[ $i -eq 0 ]]; then
  			  fdiskCommand+="n\\n\\n\\n$size\\n"
        else
          fdiskCommand+="n\\n\\n\\$size\\n"
        fi
        ;;
  		swap)
        swapPartition="$disk""$((i++))"
        if [[ $i -eq 0 ]]; then
          fdiskCommand+="n\\n\\n\\n$size\\nt\\n19\\n"
  			else
          fdiskCommand+="n\\n\\n\\n$size\\nt\\n$((i++))\\n19\\n"
        fi
        ;;
  		root)
        rootPartition="$disk""$((i++))"
        if [[ $i -eq 0 ]]; then
  			  fdiskCommand+="n\\n\\n\\n$size\\nt\\n20\\n"
        else
          fdiskCommand+="n\\n\\n\\n$size\\nt\\n$((i++))\\n20\\n"
        fi
        ;;
  		*)
  			printf "Invalid partition scheme\n"
  			exit 1
  			;;
  	esac
  done
}
function mbrDisk(){
  for i in ${!diskLayout[@]}; do
    type="${diskLayout[i]:0:4}"
    size="${diskLayout[i]:4}"
    case "${type,,}" in
      boot)
        bootPartition="$disk""$((i++))"
        if [[ $i -eq 0 ]]; then
          fdiskCommand+="n\\np\\n\\n\\n$size\\n"
        else
          fdiskCommand+="n\\np\\n\\n\\n$size\\n"
        fi
        ;;
      swap)
        swapPartition="$disk""$((i++))"
        if [[ $i -eq 0 ]]; then
          fdiskCommand+="n\\np\\n\\n\\n$size\\nt\\n82\\n"
        else
          fdiskCommand+="n\\np\\n\\n\\n$size\\nt\\n$((i++))\\n82\\n"
        fi
        ;;
      root)
        rootPartition="$disk""$((i++))"
        if [[ $i -eq 0 ]]; then
          fdiskCommand+="n\\np\\n\\n\\n$size\\nt\\n83\\n"
        else
          fdiskCommand+="n\\np\\n\\n\\n$size\\nt\\n$((i++))\\n83\\n"
        fi
        ;;
      *)
        printf "Invalid partition layout '%s'\n" "$i"
        exit 1
    esac
  done
}
function getTargetDisk(){
  availableDisks=($(lsblk -dn -o NAME | grep -v "loop\|ram\|sr"))
  n=0
  
  printf "[+] Looking for disks in the system...\n"
  
  for disk in ${availableDisks[@]}; do
      printf "%i: %s - size %s\n" "$n" "/dev/$disk" "$(lsblk -o SIZE /dev/$disk | grep -v 'SIZE' | head -1)" 
      ((++n))  
  done
  
  while true; do
    read -p "[?] Which disk to use? " ans
    if [[ $ans =~ ^[0-9]$ ]] && (( ans < ${#availableDisks[@]} && ans >= 0 )); then
      disk=${availableDisks[ans]}  
      break
    else
      continue
    fi
  done
  printf "Chosen disk %s\n" "/dev/$disk"
  disk="/dev/$disk"
}

# If disk variable is empty (default), guide the user through disk choice
if [[ -z "$disk" ]]; then
  getTargetDisk
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

# Wipe existing signatures and partition table entries
sgdisk -Z "$disk"
fdiskCommand=""

case "${partitionScheme,,}" in
	gpt)
		fdiskCommand+="g\\n"
		gptDisk
    ;;
	mbr)
		fdiskCommand+="o\\n"
		mbrDisk
    ;;
	*)
		printf "[!] Detected wrong partitioning scheme '%s'\n" "${partitionScheme,,}"
		exit 1
		;;
esac

fdiskCommand+="w"
# Partition the disk 
echo -e "$fdiskCommand" | fdisk "$disk"
partprobe "$disk"

# - FORMAT DISK PARTITIONS
# Boot partition 
mkfs.vfat -F 32 "$bootPartition"
# Rootfs partition
mkfs.ext4 "$rootPartition"
# Swap partition
mkswap "$swapPartition"

# - MOUNT PARTITIONED DISK
mount "$rootPartition" /mnt
mkdir -p /mnt/boot/efi
mount "$bootPartition" /mnt/boot/efi 
swapon "$swapPartition"
