#!/bin/bash
disk=(root+1G swap+8G root+30G)
partitionScheme="gpt"
fdiskCommand=""

case "${partitionScheme,,}" in
	gpt)
		fdiskCommand+="g\\n"
		;;
	mbr)
		fdiskCommand+="o\\n"
		;;
	*)
		printf "[!] Detected wrong partition scheme '%s'\n" "${partitionScheme,,}"
		exit 1
		;;
esac

for i in ${disk[@]}; do
	type="${i:0:4}"
	size="${i:4}"
	case "${type,,}" in
		boot)
			fdiskCommand+="n\\n\\n\\n$size\\n"
			;;
		swap)
			fdiskCommand+="n\\n\\n\\n$size\\n"
			;;
		root) 
			fdiskCommand+="n\\n\\n\\n$size\\n"
			;;
		*)
			printf "Invalid partition scheme\n"
			exit 1
			;;
	esac
done

fdiskCommand+="w"

printf "command -> %s\n" "$fdiskCommand"
