#!/bin/bash

echo "Android in a Box - Installer"
echo
echo
echo "IMPORTANT: THIS IS ALPHA LEVEL SOFTWARE. EXPECT INSTABILITY AND"
echo "           BUGS !!!!!"
echo
echo "IMPORTANT: ALSO PLEASE BE AWARE THAT WE DON'T PROVIDE FULL"
echo "           CONFINEMENT FOR THE SNAP YET !!!!"
echo
echo
echo "PLEASE NOTE: This script will require root access on your system"
echo "to install all necessary things. It will prompt you to enter your"
echo "password when required."
echo
echo

if [ "$(id -u)" -eq 0 ] ; then
	echo "ERROR: Don't run the anbox-installer as root or via sudo. Simply"
	echo "       invoke it with your regular user. The script will use sudo"
	echo "       on its own when needed."
	exit 1
fi

#Array of supported distributions. Just add any working distributions here
#Careful: LinuxMint will do systemd installation because the version number won't match Ubuntu's. If you add a distribution without systemd which does not follow the same numbering as Ubuntu, it will try systemd installation instead of Upstart

supported_dist=("Ubuntu" "LinuxMint")
DISTRIB_ID="$(lsb_release -i -s)"

function contains() {
    local n=$#
    local value=${!n}
    for ((i=1;i < $#;i++)) {
        if [ "${!i}" == "${value}" ]; then
		echo "y"
            	return 0
        fi
    }
    return 1
}

if [ "$(contains "${supported_dist[@]}" "$DISTRIB_ID")" != "y" ]; then
	echo "ERROR: You are running the installer on an unsupported distribution."
	echo "       At the moment we only support the following distributions:" 
	echo
	printf "%s, " "${supported_dist[@]}" | cut -d "," -f 1-${#supported_dist[@]}
	echo
	echo "If your distribution is in the list but you still see this message, open an issue here: https://github.com/anbox/anbox-installer"
	exit 1
fi

echo
echo "What do you want to do?"
echo
echo " 1. Install Anbox"
echo " 2. Uninstall Anbox"
echo
echo "Please enter your choice [1-2]: "
read action
echo
echo

if [ "$action" == "2" ]; then
	echo "This will now remove the Android in a Box runtime environment"
	echo "from your device. Do you really want this?"
	echo
	echo "Please be aware that this will also remove any user data"
	echo "stored inside the runtime environment."
	echo
	echo "Please type 'I AGREE' followed by pressing ENTER to continue"
	echo "or type anything else to abort:"
	read input
	if [ "$input" != "I AGREE" ]; then
		exit 1
	fi
	echo
	set -x
	if [ -e $HOME/.config/upstart/anbox.conf ]; then
		initctl stop anbox
		rm -f $HOME/.config/upstart/anbox.conf
	elif [ -e $HOME/.config/systemd/user/anbox.service ]; then
		systemctl --user stop anbox
	fi
	sudo systemctl stop snap.anbox.container-manager
	sudo snap remove anbox
	sudo rm -f /etc/udev/rules.d/99-anbox.rules
	sudo rm -f /etc/modules-load.d/anbox.conf
	sudo rmmod ashmem_linux binder_linux || true
	sudo apt purge -y anbox-modules-dkms
	if [ -e /etc/apt/sources.list.d/morphis-ubuntu-anbox-support-xenial.list ]; then
		sudo apt install -y ppa-purge
		sudo ppa-purge ppa:morphis/anbox-support
	fi
	rm -f $HOME/.config/upstart/anbox.conf
	sudo rm -f /etc/X11/Xsession.d/68anbox
	set +xe
	echo
	echo "Successfully removed anbox!"
	echo
	exit 0
fi

if [ "$action" != "1" ]; then
	echo "ERROR: Invalid option selected!"
	exit 1
fi

echo "This is the installer for the anbox runtime environment. It will"
echo "install certain things on your system to ensure all requirements"
echo "are available for anbox to work correctly."
echo
echo "In summary we will install the following things:"
echo
echo " * Add the anbox-support ppa ppa:morphis/anbox-support to the"
echo "   host system"
echo " * Install the anbox-modules-dkms deb package from the ppa"
echo "   which will add kernel modules for ashmem and binder which are"
echo "   required for the Android container to work."
echo " * Configure binder and ashmem kernel modules to be loaded"
echo "   automatically on boot."
echo " * Add an upstart job for the current user $USER which will"
echo "   start the anbox runtime on login."
echo " * Add a X11 session configuration file to allow the system"
echo "   application launcher (Unity7, Gnome Shell, ..) to find"
echo "   available Android applications."
echo
echo "Please type 'I AGREE' followed by pressing ENTER to continue"
echo "or type anything else to abort:"
read input
if [ "$input" != "I AGREE" ]; then
	exit 1
fi
echo
echo

echo "Starting installation process ..."
echo

set -ex

if [ ! -e /etc/udev/rules.d/99-anbox.rules ]; then
	sudo tee /etc/udev/rules.d/99-anbox.rules &>/dev/null <<"EOF"
KERNEL=="binder", NAME="%k", MODE="0666"
KERNEL=="ashmem", NAME="%k", MODE="0666"
EOF
fi

sudo apt install -y software-properties-common linux-headers-generic
sudo add-apt-repository -y 'ppa:morphis/anbox-support'
sudo apt update
sudo apt install -y anbox-modules-dkms

if [ ! -e /etc/modules-load.d/anbox.conf ]; then
	sudo tee /etc/modules-load.d/anbox.conf &>/dev/null <<EOF
ashmem_linux
binder_linux
EOF
fi

sudo modprobe binder_linux
sudo modprobe ashmem_linux

if snap list anbox >/dev/null 2>&1; then
	 sudo snap refresh anbox
else
	 sudo snap install --edge --devmode anbox
fi

if [ ! -e /etc/X11/Xsession.d/68anbox ]; then
	echo "Installing application launcher detection for X11 .."
	sudo tee /etc/X11/Xsession.d/68anbox &>/dev/null <<"EOF"
# This file is sourced by Xsession(5), not executed.
# Add additional anbox desktop path
if [ -z "$XDG_DATA_DIRS" ]; then
    # 60x11-common_xdg_path does not always set XDG_DATA_DIRS
    # so we ensure we have sensible defaults here (LP: #1575014)
    # as a workaround
    XDG_DATA_DIRS=/usr/local/share/:/usr/share/:$HOME/snap/anbox/common/app-data
else
    XDG_DATA_DIRS="$XDG_DATA_DIRS":$HOME/snap/anbox/common/app-data
fi
export XDG_DATA_DIRS
EOF
fi

if [ "$(contains "${supported_dist[@]}" "$DISTRIB_ID")" == "y" ]; then
	case "$(lsb_release -r -s)" in
		14.04|16.04)
			if [ ! -e $HOME/.config/upstart/anbox.conf ]; then
				mkdir -p $HOME/.config/upstart
				echo "Installing upstart session job .."
				cat <<-EOF > $HOME/.config/upstart/anbox.conf
				start on started unity7
				respawn
				respawn limit 10 5
				exec /snap/bin/anbox session-manager
				EOF
			fi
			initctl start anbox
			;;
		*)
			if [ ! -e $HOME/.config/systemd/user/anbox.service ] ; then
				mkdir -p $HOME/.config/systemd/user
				echo "Installing systemd user session service .."
				cat <<-EOF > $HOME/.config/systemd/user/anbox.service
				[Unit]
				Description=Anbox session manager

				[Service]
				ExecStart=/snap/bin/anbox session-manager

				[Install]
				WantedBy=default.target
				EOF
				systemctl --user daemon-reload
				systemctl --user enable --now anbox
			fi
			;;
	esac
fi

set +x

echo
echo "Done!"
echo
echo "To ensure all changes made to your system you should now reboot"
echo "your system. If you don't do this no Android applications will"
echo "show up in the system application launcher."
