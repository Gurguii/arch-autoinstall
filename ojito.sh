#!/bin/bash
source "test.sh"
cat << EOF >> file
${test['gnome']}
a ver si funciona
$(if [[ ${test['gnome']} == 'gnome gdm' ]]; then echo "true"; else echo 'false'; fi)
EOF
