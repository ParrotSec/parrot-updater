#!/bin/bash
set -e
DEBIAN_FRONTEND=noninteractive
export BLUE='\033[1;94m'
export GREEN='\033[1;92m'
export RED='\033[1;91m'
export RESETCOLOR='\033[1;00m'

function update_notify_counter() {
	if [ -f ~/.last-updated ]; then
		rm ~/.last-updated
		date -u > ~/.last-updated
	else
		date -u > ~/.last-updated
	fi
}


function send_notify() {
	notify-send -t 5000 -a "Parrot Updater" -i /usr/share/icons/parrot-logo-100.png "Parrot Updater" "<b>Update</b> your system to apply the latest security updates and import the latest features"
}


function notify_reminder() {
	zenity --question --text="Do you want to check for updates?" && \
	gksu -- x-terminal-emulator -e parrot-upgrade | zenity --progress --pulsate --auto-close --auto-kill --text="Installing updates" && \
	zenity --info "Upgrade completed" && update_notify_counter
}


function start_scheduled() {
	if [ -d /lib/live/mount/rootfs/filesystem.squashfs ]; then
		exit 0
	else
		if [ -f ~/.last-updated ]; then
			if test `find ~/.last-updated -mmin +10080`; then
				send_notify
				sleep 50
				notify_reminder
			fi
		else
			update_notify_counter
			send_notify
			sleep 20
			notify_reminder
		fi
	fi
}


case "$1" in
	scheduled)
		start_scheduled
	;;
	start)
		notify_reminder
	;;
   *)
echo -e "
Parrot Update Reminder (v 0.6)
	Developed by Lorenzo \"Palinuro\" Faletra <palinuro@parrotsec.org>
		and a huge amount of Caffeine + some GNU/GPL v3 stuff
	Usage:
	$RED┌──[$GREEN$USER$YELLOW@$BLUE`hostname`$RED]─[$GREEN$PWD$RED]
	$RED└──╼ \$$GREEN"" update-reminder $RED{$GREEN""scheduled$RED|$GREEN""start$RED""}

	$RED scheduled$BLUE -$GREEN Check when the system was updated and start only if needed
	$RED start$BLUE -$GREEN Start the notifier now
$RESETCOLOR
" >&2

exit 1
;;
esac
