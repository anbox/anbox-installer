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

if [ "$(lsb_release -i -s)" != "Ubuntu" ]; then
	echo "ERROR: You are running the installer on a not support distribution."
	echo "       At the moment we only support Ubuntu."
	exit 1
fi

echo
echo "What do you want to do?"
echo
echo " 1. Install Anbox"
echo " 2. Uninstall Anbox"
echo
echo "Please enter your choice: "
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
	if [ -x $HOME/.config/upstart/anbox.conf ]; then
		initctl stop anbox
		rm $HOME/.config/upstart/anbox.conf
	fi
	sudo systemctl stop snap.anbox.container-manager
	sudo snap remove anbox
	sudo rmmod ashmem_linux || true
	sudo rmmod binder_linux || true
	if [ -e /etc/udev/rules.d/99-anbox.rules ]; then
		sudo rm /etc/udev/rules.d/99-anbox.rules
	fi
	if [ -e /etc/udev/rules.d/anbox.conf ]; then
		sudo rm /etc/modules-load.d/anbox.conf
	fi
	sudo rmmod ashmem_linux binder_linux || true
	sudo apt purge -y anbox-modules-dkms
	if [ -e /etc/apt/sources.list.d/morphis-ubuntu-anbox-support-xenial.list ]; then
		sudo apt install -y ppa-purge
		sudo ppa-purge ppa:morphis/anbox-support
	fi
	if [ -e $HOME/.config/upstart/anbox.conf ]; then
		rm $HOME/.config/upstart/anbox.conf
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
echo " * Add an upstart job for the current user $USER which will"
echo "   start the anbox runtime on login."
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

sudo apt install -y software-properties-common
sudo add-apt-repository -y -u 'ppa:morphis/anbox-support'
sudo apt install -y anbox-modules-dkms

if [ ! -e /etc/modules-load.d/anbox.conf ]; then
	sudo tee /etc/modules-load.d/anbox.conf &>/dev/null <<EOF
ashmem_linux
binder_linux
EOF
fi

sudo modprobe binder_linux
sudo modprobe ashmem_linux

snap list | grep anbox
if [ $? -ne 1 ]; then
	 sudo snap install --edge --devmode anbox
else
	 sudo snap refresh anbox
fi

if [ ! -e $HOME/.config/upstart/anbox.conf ]; then
	echo "Installing upstart session job .."
	cat << EOF > $HOME/.config/upstart/anbox.conf
start on unity7
respawn
respawn limit 10 5
exec /snap/bin/anbox session-manager
EOF
fi

initctl start anbox
set +x

echo
echo "Done!"
