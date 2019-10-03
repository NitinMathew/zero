#!/bin/bash

echo "Starting installation
sudo apt-get update
sudo apt-get upgrade

#Setup Otgmode
echo "dtoverlay=dwc2" | sudo tee -a /boot/config.txt
echo "dwc2" | sudo tee -a /etc/modules

#keyboard
sudo gcc  hid-gadget-test.c -o hid-gadget-test
sudo chmod -x hid-gadget-test

#make it happen on boot
mv enableHid.sh /home/pi/
mv hid.sh /home/pi/

#rc.local entry
mv /etc/rc.local /etc/rc.local.tmp
mv rcentry/rc.local /etc/rc.local
