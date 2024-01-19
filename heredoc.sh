#!/bin/bash
# 1st test
prompt=1

cat << EOF >> testing
$(if (( $prompt )); then read -s -p "smth: " st; echo "pass=$st"; fi)
EOF

# 2nd test
declare -A test
test['gnome']='gnome gdm'
cat << EOF >> file
${test['gnome']}
a ver si funciona
$(if [[ ${test['gnome']} == 'gnome gdm' ]]; then echo "true"; else echo 'false'; fi)
EOF
