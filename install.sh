#!/bin/bash



# get DIR the script is running from (by CD'ing in and running pwd
wdir=$( cd $(dirname $BASH_SOURCE[0]) && pwd)

# check for wifi capability
if $wdir/wifi/check_wifi.sh; then WIFI=true; else WIFI=false; fi

# check Internet conectivity against 
echo "Testing Internet connection and name resolution..."
if [ "$(curl -s http://www.msftncsi.com/ncsi.txt)" != "Microsoft NCSI" ]; then 
        echo "...[Error] No Internet connection or name resolution doesn't work! Exiting..."
        exit
fi
echo "...[pass] Internet connection works"

# check for Raspbian Jessie
echo "Testing if the system runs Raspbian Jessie or Stretch..."
if ! (grep -q -E "Raspbian.*jessie" /etc/os-release || grep -q -E "Raspbian.*stretch" /etc/os-release) ; then
        echo "...[Error] Pi is not running Raspbian Jessie or Stretch! Exiting ..."
        exit
fi
echo "...[pass] Pi seems to be running Raspbian Jessie or Stretch"
if (grep -q -E "Raspbian.*stretch" /etc/os-release) ; then
	STRETCH=true
fi


echo "Backing up resolv.conf"
sudo cp /etc/resolv.conf /tmp/resolv.conf

echo "Installing needed packages..."
sudo apt-get -y update
sudo apt-get -y upgrade # include patched bluetooth stack
#if $WIFI; then
#	sudo apt-get install -y dnsmasq git python-pip python-dev screen sqlite3 inotify-tools hostapd
#else
#	sudo apt-get install -y dnsmasq git python-pip python-dev screen sqlite3 inotify-tools
#fi

# hostapd gets installed in even if WiFi isn't present (SD card could be moved from "Pi Zero" to "Pi Zero W" later on)
sudo apt-get -y install dnsmasq git python-pip python-dev screen sqlite3 inotify-tools hostapd autossh bluez bluez-tools bridge-utils ethtool  policykit-1 tshark tcpdump iodine


# at this point the nameserver in /etc/resolv.conf is set to 127.0.0.1, so we replace it with 8.8.8.8
#	Note: 
#	A better way would be to backup before dnsmasq install, with
#		$ sudo bash -c "cat /etc/resolv.conf > /tmp/backup"
#	and restore here with
#		$ sudo bash -c "cat /tmp/backup > /etc/resolv.conf"
sudo bash -c "cat /tmp/resolv.conf > /etc/resolv.conf"
# append 8.8.8.8 as fallback secondary dns
sudo bash -c "echo nameserver 8.8.8.8 >> /etc/resolv.conf"

# install pycrypto
echo "Installing needed python additions..."
mv setup.cfg setup.bkp
sudo pip install pycrypto # already present on stretch
sudo pip install pydispatcher
mv setup.bkp setup.cfg

# disable interfering services
echo "Disabeling unneeded services to shorten boot time ..."
sudo update-rc.d ntp disable # not needed for stretch (only jessie)
sudo update-rc.d avahi-daemon disable
sudo update-rc.d dhcpcd disable
sudo update-rc.d networking disable
sudo update-rc.d avahi-daemon disable
sudo update-rc.d dnsmasq disable # we start this by hand later on

echo "Create udev rule for HID devices..."
# rule to set access rights for /dev/hidg* to 0666 
echo 'SUBSYSTEM=="hidg",KERNEL=="hidg[0-9]", MODE="0666"' > /tmp/udevrule
sudo bash -c 'cat /tmp/udevrule > /lib/udev/rules.d/99-usb-hid.rules'

echo "Enable SSH server..."
sudo update-rc.d ssh enable

echo "Checking network setup.."
# set manual configuration for usb0 (RNDIS) if not already done
if ! grep -q -E '^iface usb0 inet manual$' /etc/network/interfaces; then
	echo "Entry for manual configuration of RNDIS interface not found, adding..."
	sudo /bin/bash -c "printf '\niface usb0 inet manual\n' >> /etc/network/interfaces"
else
	echo "Entry for manual configuration of RNDIS interface found"
fi

# set manual configuration for usb1 (CDC ECM) if not already done
if ! grep -q -E '^iface usb1 inet manual$' /etc/network/interfaces; then
	echo "Entry for manual configuration of CDC ECM interface not found, adding..."
	sudo /bin/bash -c "printf '\niface usb1 inet manual\n' >> /etc/network/interfaces"
else
	echo "Entry for manual configuration of CDC ECM interface found"
fi

# overwrite Responder configuration
echo "Configure Responder..."
sudo mkdir -p /var/www
sudo chmod a+r /var/www
cp conf/default_Responder.conf Responder/Responder.conf
sudo cp conf/default_index.html /var/www/index.html
sudo chmod a+r /var/www/index.html


# create 128 MB image for USB storage
echo "Creating 128 MB image for USB Mass Storage emulation"
mkdir -p $wdir/USB_STORAGE
dd if=/dev/zero of=$wdir/USB_STORAGE/image.bin bs=1M count=128
mkdosfs $wdir/USB_STORAGE/image.bin

# create folder to store loot found
mkdir -p $wdir/collected


# create systemd service unit for Zero startup
# Note: switched to multi-user.target to make nexmon monitor mode work
if [ ! -f /etc/systemd/system/Zero.service ]; then
        echo "Injecting Zero startup script..."
        cat <<- EOF | sudo tee /etc/systemd/system/Zero.service > /dev/null
                [Unit]
                Description=Zero Startup Service
                #After=systemd-modules-load.service
                After=local-fs.target
                DefaultDependencies=no
                Before=sysinit.target

                [Service]
                #Type=oneshot
                Type=forking
                RemainAfterExit=yes
                ExecStart=/bin/bash $wdir/boot/boot_Zero
                StandardOutput=journal+console
                StandardError=journal+console

                [Install]
                WantedBy=multi-user.target
                #WantedBy=sysinit.target
EOF
fi

sudo systemctl enable Zero.service

if ! grep -q -E '^.+Zero STARTUP$' /home/pi/.profile; then
	echo "Adding Zero startup script to /home/pi/.profile..."
cat << EOF >> /home/pi/.profile
# Zero STARTUP
source /tmp/profile.sh
declare -f onLogin > /dev/null && onLogin
EOF
fi

# removing FSCK from fstab, as this slows down boot (jumps in on stretch nearly every boot)
echo "Disable FSCK on boot ..."
sudo sed -i -E 's/[12]$/0/g' /etc/fstab

# enable autologin for user pi (requires RASPBIAN JESSIE LITE, should be checked)
echo "Enable autologin for user pi..."
sudo ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service

# setup USB gadget capable overlay FS (needs Pi Zero, but shouldn't be checked - setup must 
# be possible from other Pi to ease up Internet connection)
echo "Enable overlay filesystem for USB gadgedt suport..."
sudo sed -n -i -e '/^dtoverlay=/!p' -e '$adtoverlay=dwc2' /boot/config.txt

# add libcomposite to /etc/modules
echo "Enable kernel module for USB Composite Device emulation..."
if [ ! -f /tmp/modules ]; then sudo touch /etc/modules; fi
sudo sed -n -i -e '/^libcomposite/!p' -e '$alibcomposite' /etc/modules

echo "Removing all former modules enabled in /boot/cmdline.txt..."
sudo sed -i -e 's/modules-load=.*dwc2[',''_'a-zA-Z]*//' /boot/cmdline.txt

echo "Installing kernel update ..."
# still needed on current stretch releas, kernel 4.9.41+ ships still
# with broken HID gadget module (installing still needs a cup of coffee)
# Note:  last working Jessie version was the one with kernel 4.4.50+
#        stretch kernel known working is 4.9.45+ (only available via update right now)

# Raspbian stretch with Kernel >= 4.9.50+ needed for working bluetooth nap
#sudo rpi-update 913eddd6d23f14ce34ae473a4c080c5c840ed583 # force kernel 4.9.51+ for nexmon compatability

# Raspbian stretch with Kernel >= 4.9.78+ (working bluetooth, nexmon module compiled for this version)
sudo rpi-update 23a007716a0c6a8677097be859cf7063ae093d27

# ToDo: the correct branch of nexmon for the current update kernel should be checked out here,
#       to do this the downloaded kernel version has to be feteched, which is only available after reboot from `uname -r`
#       The logic to do this will be implemented in init_wifi_nexmon, to allow checking out the correct branch of "Zero_nexmon_addition"
#       if it doesn't match the current kernel at runtime


echo "Generating keypair for use with AutoSSH..."
source $wdir/setup.cfg

mkdir -p -- "$(dirname -- "$AUTOSSH_PRIVATE_KEY")"

ssh-keygen -q -N "" -C "Zero" -f $AUTOSSH_PRIVATE_KEY && SUCCESS=true
if $SUCCESS; then
        echo "... keys created"
        echo
        echo "Use \"$wdir/ssh/pushkey.sh\""
        echo "in order to promote the public key to a remote SSH server"
else
	echo "Creation of SSH key pair failed!"
fi


echo
echo
echo "===================================================================================="
echo "If you came till here without errors, you shoud be good to go with your Zero..."
echo "...if not - sorry, you're on your own, as this is work in progress"
echo 
echo "Attach Zero to a host and you should be able to SSH in with pi@172.16.0.1 (via RNDIS/CDC ECM)"
echo
echo "If you use a USB OTG adapter to attach a keyboard, Zero boots into interactive mode"
echo
echo "If you're using a Pi Zero W, a WiFi AP should be opened. You could use the AP to setup Zero, too."
echo "          WiFi name:    Zero"
echo "          Key:          1234Zero"
echo "          SSH access:    pi@172.24.0.1 (password: raspberry)"
echo
echo "  or via Bluetooth NAP:    pi@172.26.0.1 (password: raspberry)"
echo
echo "Go to your installation directory. From there you can alter the settings in the file 'setup.cfg',"
echo "like payload and language selection"
echo 
echo "If you're using a Pi Zero W, give the HID backdoor a try ;-)"
echo
echo "You need to reboot the Pi now!"
echo "===================================================================================="

