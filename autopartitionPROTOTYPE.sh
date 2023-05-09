#!/bin/bash
function gptDisk(){
  for i in ${!disk[@]}; do
  	type="${disk[i]:0:4}"
  	size="${disk[i]:4}"
  	case "${type,,}" in
  		boot)
        if [[ $i -eq 0 ]]; then 
  			  fdiskCommand+="n\\n\\n\\n$size\\n\\n1\\n"
        else
          fdiskCommand+="n\\n\\n\\$size\\nt\\n$(i++)\\n19\\n"
        fi
        ;;
  		swap)
        if [[ $i -eq 0 ]]; then
          fdiskCommand+="n\\n\\n\\n$size\\nt\\n19\\n"
  			else
          fdiskCommand+="n\\n\\n\\n$size\\nt\\n$(i++)\\n19\\n"
        fi
        ;;
  		root) 
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
  for i in ${!disk[@]}; do
    type="${disk[i]:0:4}"
    size="${disk[i]:4}"
    case "${type,,}" in
      boot)
        if [[ $i -eq 0 ]]; then
          fdiskCommand+="n\\np\\n\\n\\n$size\\nt\\n01\\n"
        else
          fdiskCommand+="n\\np\\n\\n\\n$size\\nt\\n$((i++))\\n01\\n"
        fi
        ;;
      swap)
        if [[ $i -eq 0 ]]; then
          fdiskCommand+="n\\np\\n\\n\\n$size\\nt\\n82\\n"
        else
          fdiskCommand+="n\\np\\n\\n\\n$size\\nt\\n$((i++))\\n82\\n"
        fi
        ;;
      root)
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

disk=(boot+1G swap+8G root+30G)
partitionScheme="mbr"
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

# 'fdisk -w always -W always' -> always wipe partition/disk signatures (avoid prompt which makes automatising a pain)
printf "command -> %s\n" "echo -e \"$fdiskCommand\" | fdisk -w always -W always /dev/<disk>"
