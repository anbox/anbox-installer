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

SUPPORTED_DISTROS=("Ubuntu" "LinuxMint" "neon" "elementary")
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

if [ "$(contains "${SUPPORTED_DISTROS[@]}" "$DISTRIB_ID")" != "y" ]; then
	echo "ERROR: You are running the installer on an unsupported distribution."
	echo "       At the moment we only support the following distributions:" 
	echo
	printf "%s, " "${SUPPORTED_DISTROS[@]}" | cut -d "," -f 1-${#SUPPORTED_DISTROS[@]}
	echo
	echo "If your distribution is in the list but you still see this message, open"
	echo "an issue here: https://github.com/anbox/anbox-installer"
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
	sudo snap remove anbox
	sudo apt purge -y anbox-modules-dkms
	if [ -e /etc/apt/sources.list.d/morphis-ubuntu-anbox-support-xenial.list ]; then
		sudo apt install -y ppa-purge
		sudo ppa-purge ppa:morphis/anbox-support
	fi
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
echo " * Install the anbox-common package from the ppa which will"
echo "   - Add an upstart job for the current user $USER which will"
echo "     start the anbox runtime on login."
echo "   - Add a X11 session configuration file to allow the system"
echo "     application launcher (Unity7, Gnome Shell, ..) to find"
echo "     available Android applications."
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

sudo apt install -y software-properties-common linux-headers-generic
sudo add-apt-repository -y 'ppa:morphis/anbox-support'
sudo apt update
sudo apt install -y anbox-modules-dkms anbox-common

if snap info anbox | grep -q "installed:" ; then
	 sudo snap refresh --edge anbox || true
else
	 sudo snap install --edge --devmode anbox
fi

set +x

echo
echo "Done!"
echo
echo "To ensure all changes made to your system you should now reboot"
echo "your system. If you don't do this no Android applications will"
echo "show up in the system application launcher."
