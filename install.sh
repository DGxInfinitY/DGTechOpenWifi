#!/bin/bash
# Define a few things b4 we start
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
GETMAC=$(iw wlan0 info | grep addr | cut -b 7-23)
#Check if root
if (( $EUID != 0 )); then
    echo -e "${RED}Please run this script as root(${BLUE}sudo ./install.sh${RED})${NC}"
    exit 0
fi
#Start Script
echo -e "${BLUE}#"
echo -e "#"
echo -e "# This Script is Developed by Donovan Goodwin of DGTech Industries for use with the DGTechOpenWifi system."
echo -e "#"
echo -e "#${NC}"
# Create a Virtual AP Device at Boot that has unique MAC address for each device(MAC collected using iw)
# Appened to a file in the home directory
echo -e "${GREEN}Creating Boot up Config File for ap0${NC}"
echo 'SUBSYSTEM=="ieee80211", ACTION=="add|change", ATTR{macaddress}=="'${GETMAC}'", KERNEL=="phy0", \' > /home/pi/70-persistent-net.rules
echo '  RUN+="/sbin/iw phy phy0 interface add ap0 type __ap", \' >> "/home/pi/70-persistent-net.rules"
echo '  RUN+="/bin/ip link set ap0 address '${GETMAC}'"' >> "/home/pi/70-persistent-net.rules"
echo -e "${GREEN}Done.${NC}"
# Move to correct location
echo -e "${GREEN}Moving to /etc/udev/rules.d/"
sudo mv /home/pi/70-persistent-net.rules /etc/udev/rules.d/
sleep 1
echo -e "${GREEN}Done.${NC}"
sleep 1
# Install the packages to create AP
echo -e "${GREEN}Installing Required Packages for DGTechOpenWifi... ${NC}"
sudo apt-get install dnsmasq hostapd openvpn -y
sleep 1
# Next we modify the dnsmasq.conf file to our liking.
echo -e "${GREEN}Creating Config for dnsmasq${NC}"
sudo rm /etc/dnsmasq.conf
sudo touch /etc/dnsmasq.conf
sudo cat <<EOT >> /etc/dnsmasq.conf
interface=lo,ap0
no-dhcp-interface=lo,wlan0
bind-interfaces
server=8.8.8.8
domain-needed
bogus-priv
dhcp-range=192.168.10.50,192.168.10.150,12h
EOT
sleep 1
echo -e "${GREEN}Done.${NC}"
# Next we modify the file at /etc/hostapd/hostapd.conf
echo -e "${GREEN}Now we create the hostapd configuration${NC}"
sudo rm /etc/hostapd/hostapd.conf
sudo touch /etc/hostapd/hostapd.conf
sudo cat <<EOT >> /etc/hostapd/hostapd.conf
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
interface=ap0
driver=nl80211
ssid=DGTechOpenWifi
hw_mode=g
channel=11
wmm_enabled=0
macaddr_acl=0
auth_algs=1
# Uncomment all lines with wpa if you want a secured network (IE a network with a password)
# wpa=2
# wpa_passphrase=YourPassPhraseHere
# wpa_key_mgmt=WPA-PSK
# wpa_pairwise=TKIP CCMP
rsn_pairwise=CCMP
EOT
echo -e "${GREEN}Done.${NC}"
sleep 1
# Now we modify the the Hostapd to use our configuration
echo -e "${GREEN}Now we enable our configuration${NC}"
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd
sleep 1
echo -e "${GREEN}Done.${NC}"
sleep 1
# This part is where some user configuration needs to happen. You are going to need to add your own wifi networks that you want to connect to.
echo -e "${GREEN}Now we configure default networks, this needs to be hand configured afterwards. (/etc/wpa_supplicant/wpa_supplicant.conf)${NC}"
sleep 5
sudo rm /etc/wpa_supplicant/wpa_supplicant.conf
sudo touch /etc/wpa_supplicant/wpa_supplicant.conf
sudo cat <<EOT >> /etc/wpa_supplicant/wpa_supplicant.conf
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
network={
        ssid="network"
        psk="password"
        id_str="School"
}

network={
        ssid="secondnetwork"
        psk="secondpassword"
        id_str="Home"
}
EOT
# Next we modify /etc/network/interfaces to support our new AP
echo -e "${GREEN}Now configuring network interfaces...${NC}"
sudo rm /etc/network/interfaces
sudo touch /etc/network/interfaces
sudo cat <<EOT >> /etc/network/interfaces
source-directory /etc/network/interfaces.d

auto lo
auto ap0
auto wlan0
iface lo inet loopback

allow-hotplug ap0
iface ap0 inet static
    address 192.168.10.1
    netmask 255.255.255.0
    hostapd /etc/hostapd/hostapd.conf

allow-hotplug wlan0
iface wlan0 inet manual
    wpa-roam /etc/wpa_supplicant/wpa_supplicant.conf
iface Home inet dhcp
iface School inet dhcp

EOT
echo -e "${GREEN}Done.${NC}"
sleep 1
# Next we implore a workaround to get everything situated after boot
echo -e "${GREEN}Creating Startup Script...${NC}"
cat <<EOT >> /tmp/start-ap-managed-wifi.sh
#!/bin/bash
sleep 30
echo "Now starting DGTechOpenWifi"
sleep 1
echo "Configuring Interfaces"
sleep 1
echo "Bringing Down wlan0"
sudo ifdown --force wlan0
sleep 1
echo "Done"
sleep 1
echo "Bringing Down ap0"
sudo ifdown --force ap0
sleep 1
echo "Done"
sleep 1
echo "Bringing up ap0"
sudo ifup ap0
sleep 1
echo "Done"
sleep 1
echo "Bringing up wlan0"
sudo ifup wlan0
echo "Done"
sleep 2
echo "Bridging Host and Client Networks"
sudo sysctl -w net.ipv4.ip_forward=1
echo "Adding iptables masquerade reroute"
sudo iptables -t nat -A POSTROUTING -s 192.168.10.0/24 ! -d 192.168.10.0/24 -j MASQUERADE
echo "Done"
echo "Restarting dnsmasq"
sudo systemctl restart dnsmasq
echo "Done"
echo "Now connecting to VPN"
sudo openvpn --config /home/pi/DGTechOpenWifi.ovpn --daemon
echo "Done"
echo "DGTechOpenWifi Now ready to use."
exit 0
EOT
echo -e "${GREEN}Changing Permissions of Startup File.${NC}"
sudo chmod 777 /tmp/start-ap-managed-wifi.sh
sudo chmod +X /tmp/start-ap-managed-wifi.sh
echo -e "${GREEN}Moving file to /home/pi${NC}"
sudo mv /tmp/start-ap-managed-wifi.sh /home/pi/
echo -e "${GREEN}Done.${NC}"
sleep 1
# Time to create the cron job
echo -e "${GREEN}Creating new Cron Job.${NC}"
crontab -l | { cat; echo "@reboot /home/pi/start-ap-managed-wifi.sh"; } | crontab -
echo -e "${GREEN}Done.${NC}"
echo -e "${GREEN}Creating OpenVPN Config File.${NC}"
cat <<EOT >> /home/pi/DGTechOpenWifi.ovpn
# Add contents of DGTechOpenWifi.ovpn Here to connect to VPN(This is a non-free vpn service)
EOT
echo -e "${GREEN}Done.${NC}"
read -p "The system must be restarted for changes to take effect. Would you like to do that now? [y/N]" -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo -e "${GREEN}Restarting now...${NC}"
    wait 3    
    sudo reboot now
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
else
    echo "Make sure to restart later. Thanks have a nice day!"
fi
exit 0
