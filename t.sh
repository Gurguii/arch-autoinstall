#!/bin/bash
prompt=1
cat << EOF >> testing
$(if (( $prompt )); then read -s -p "smth: " st; echo "pass=$st"; fi)
EOF
