#!/bin/bash

echo "Anbox (Android in a Box) - Installer"
echo
echo
echo "IMPORTANT: This is a script, considered to be in Alpha stage."
echo "           EXPECT INSTABILITY AND BUGS !!!!!"
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

if ! uname -a | grep -q x86_64 ; then
	echo "ERROR: We only support for x86_64 devices, for now. As  "
	echo "       your system has a different architecture we can't"
	echo "       support it-at least not yet."
	exit 1
fi

SUPPORTED_DISTROS=("Ubuntu" "LinuxMint" "neon" "elementary" "Zorin")
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
read -r action
echo
echo

[[ -n "$(which snap)" ]] || {
	echo "ERROR: Your system does not support snaps. Please have a look"
	echo "       at https://snapcraft.io/ to find out how you can add"
	echo "       support for snaps on your system."
	exit 1
}

uninstall() {
	set -x
	sudo snap remove anbox
	if [ -e /etc/apt/sources.list.d/morphis-ubuntu-anbox-support-xenial.list ]; then
		ppa_purged_installed=0
		if ! dpkg --get-selections | grep -q ppa-purge ; then
			sudo apt install -y ppa-purge
			ppa_purged_installed=1
		fi
		sudo apt install -y ppa-purge
		sudo ppa-purge -y ppa:morphis/anbox-support
		if [ "$ppa_purged_installed" -eq 1 ]; then
			sudo apt purge ppa-purge
		fi
	fi
	set +x
}

if [ "$action" == "2" ]; then
	echo "This will now remove Anbox from your device."
	echo "Do you really want to do this?"
	echo
	echo "Please be aware that this will also remove any user data"
	echo "stored inside the runtime environment."
	echo
	echo "Please type 'I AGREE' followed by pressing ENTER to continue"
	echo "or type anything else to abort:"
	read -r input
	if [ "$input" != "I AGREE" ]; then
		exit 1
	fi
	echo
	uninstall
	echo
	echo "Successfully removed Anbox!"
	echo
	exit 0
fi

if [ "$action" != "1" ]; then
	echo "ERROR: Invalid option selected!"
	exit 1
fi

echo "This is the installer for the Anbox runtime environment. It will"
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
read -r input
if [ "$input" != "I AGREE" ]; then
	exit 1
fi
echo
echo

echo "Starting installation process ..."
echo

cleanup() {
	local err=$?
	trap - EXIT

	echo "ERROR: Installation failed. Removing all parts of Anbox again."
	uninstall

	exit $err
}

trap cleanup HUP PIPE INT QUIT TERM EXIT

set -ex

sudo add-apt-repository -y 'ppa:morphis/anbox-support'
# Users tend to have APT repositories installed which are not properly
# authenticated and because of that `apt update` will fail. We ignore
# this and proceed with the package installation. If the installation
# of a specific package fails this will indicate our point of abort.
sudo apt update || true
sudo apt install -y anbox-common

# Install kernel drivers only if necessary and let the user use the
# ones build into his kernel otherwise.
if [ -c /dev/binder ] && [ -c /dev/ashmem ]; then
    echo "Android binder and ashmem seems to be already enabled in kernel.";
else
    sudo apt install -y linux-headers-generic anbox-modules-dkms
    sudo modprobe binder_linux
    sudo modprobe ashmem_linux
fi

if snap info anbox | grep -q "installed:" ; then
	 sudo snap refresh --edge anbox || true
else
	 sudo snap install --edge --devmode anbox
fi

set +x

echo
echo "Done!"
echo
echo "To ensure all changes made to your system, you should now restart"
echo "your system. If you don't do this Android applications won't show"
echo "up in the system application launcher."
trap - EXIT
