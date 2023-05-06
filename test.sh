#!/bin/bash

declare -A test
test['gnome']="gnome gdm" # also 'gnome-extra'
test['lxqt']="lxqt sddm" # also 'lxqt-config lxdm'
test['kde_plasma']="plasma-meta sddm"
test['xfce']="xfce4 xdm" # also 'xfce4-goodies lightdm'
test['mate']="mate lightdm" # also 'mate-extra'
test['cinnamon']="cinnamon lightdm" # also 'cinnamon translations'
test['deepin']="deepin lightdm" # also 'deepin-extra'
test['enlightenment']="enlightenment lightdm" # also 'gdm'
test['budgie']="budgie-desktop lightdm"

for i in ${!test[@]}; do
  pack=$(echo ${test[$i]} | cut -d' ' -f1)
  dp=$(echo ${test[$i]} | cut -d' ' -f2)
  printf "[%s]\npackage: %s display manager: %s\n" "$i" "$pack" "$dp"
  read -r -p "install? y/n " ans
  if [[ ${ans,,} == "y" || ${ans,,} == "yes" ]]; then
    sudo pacman -S --noconfirm "$pack" "$dp"
  fi
done
