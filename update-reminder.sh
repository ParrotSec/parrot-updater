#!/bin/bash
set -e
DEBIAN_FRONTEND=noninteractive

notify-send -t 500000 -a "Parrot Updater" -i /usr/share/icons/parrot-logo-100.png "Parrot Updater" "<b>Update</b> your system to apply the latest security updates and import the latest features"
sleep 10

zenity --question --text="Parrot was not updated for a while, do you want to check for updates?" && \
gksu apt update | zenity --progress --pulsate --auto-close --auto-kill --text="Checking for updates" && \
zenity --question --text="$(echo $(apt list --upgradable | wc -l)-1 | bc) packages can be upgraded, do you want to upgrade them?" && \
gksu -- apt -y dist-upgrade | zenity --progress --pulsate --auto-close --auto-kill --text="Installing updates" && \
zenity --info "Upgrade completed"

if [ "$?" = -1 ] ; then
        zenity --error \
          --text="Update canceled."
fi
