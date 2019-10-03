#!/bin/bash

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

echo " updating the firmware .............................."

sudo rpi-update

echo "Rebooting the system to apply the changes"

sudo reboot

