#!/bin/bash
source garch.conf

# Map of some of the most common graphical environments
declare -A graphEnv
graphEnv['gnome']="gnome gdm" # also 'gnome-extra'
graphEnv['lxqt']="lxqt sddm" # also 'lxqt-config lxdm'
graphEnv['kde_plasma']="plasma-meta sddm"
graphEnv['xfce']="xfce4 xdm" # also 'xfce4-goodies lightdm'
graphEnv['mate']="mate lightdm" # also 'mate-extra'
graphEnv['cinnamon']="cinnamon lightdm" # also 'cinnamon translations'
graphEnv['deepin']="deepin lightdm" # also 'deepin-extra'
graphEnv['enlightenment']="enlightenment lightdm" # also 'gdm'
graphEnv['budgie']="budgie-desktop lightdm"

read -r -p "Do you want to install a graphical environment? y/n " ans
if [[ "${ans,,}" -eq "n" || "${ans,,}" -eq "no" ]]; then
  exit 1
fi
n=0
for i in ${!graphEnv[@]}; do
 gEnv=$(echo ${graphEnv[i]} | cut -d' ' -f1)
 dMan=$(echo ${graphEnv[i]} | cut -d' ' -f2)
 printf "%i - graphical environment: %s display manager: %s\n" "$n" "$graphicalEnvironment" "$displayManager"
 read -r -p "Choice: " ans
 graphicalEnvironment=$(echo ${graphEnv[ans]} | cut -d' ' -f1)
 displayManager=$(echo ${graphEnv[ans]} | cut -d' ' -f2)
done
