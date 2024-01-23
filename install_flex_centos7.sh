#!/bin/bash
echo "==============="
echo "Installing wget"
echo "==============="
sudo yum install -y wget
echo "=================="
echo "Installing lmadmin"
echo "=================="
sudo getent group lmadmin >/dev/null || groupadd -r lmadmin
sudo getent passwd lmadmin >/dev/null || useradd -d /home/lmadmin -g lmadmin -m -r lmadmin
sudo yum install -y ld-linux.so.2
LSB=$(yum provides /lib/ld-lsb.so.3 | grep lsb-core | tail -1 | cut -f 1 -d ' ')
sudo yum install -y $LSB
sudo echo "lmadmin ALL=(ALL) NOPASSWD:ALL " >> /etc/sudoers
# If Web GUI to Flex licensing is not a must - lmgrd can be used, can be placed in rc.local to startup on boot
# usage - ./lmgrd -c PATH_TO_KEY_FILE -l PATH_TO_LOG_FILE
# RW rights needed to both files
echo "==========================================================="
echo "Getting Linux 32-bit IPv6 version 11.14 from AWS FrontCloud"
echo "==========================================================="
wget http://d1g91r27pzl568.cloudfront.net/Cameo_daemon/FlexNet_11_14/ipv6/linux/lnx_32/cameo
chmod +x cameo
echo "========================================"
echo "Getting Linux 32-bit lmgrd version 11.14"
echo "========================================"
wget https://d1oqhepk9od1tu.cloudfront.net/Flex_License_Server_Utilities/v11.14/linux32/lmgrd
chmod +x lmgrd
echo "======================================"
echo "Making flex log file named FlexLog.log"
echo "======================================"
touch FlexLog.log
chmod 664 FlexLog.log
echo "=========================================="
echo "Getting Linux 32-bit lmadmin version 11.14"
echo "=========================================="
wget https://d1oqhepk9od1tu.cloudfront.net/Flex_License_Server_Utilities/v11.14/linux32/lmadmin-i86_lsb-11_14_0_0.bin
chmod +x lmadmin-i86_lsb-11_14_0_0.bin
echo "========================================="
echo "Executing lmadmin version 11.14 installer"
echo "IMPORTANT: Install into directory /opt/local/FNPLicenseServerManager"
echo ""
echo " Note:  Accept all defaults for script to work properly!!!"
read -p -"Press any key to continue ...: " -n1 -s
echo "=========================================="
sudo ./lmadmin-i86_lsb-11_14_0_0.bin
sudo mkdir -p /opt/local/FNPLicenseServerManager/licenses/cameo/
sudo mv cameo /opt/local/FNPLicenseServerManager/licenses/cameo/cameo
sudo mv lmgrd /opt/local/FNPLicenseServerManager/lmgrd
sudo mv cameo /opt/local/FNPLicenseServerManager/cameo
sudo mv FlexLog.log /opt/local/FNPLicenseServerManager/FlexLog.log
sudo chown -R lmadmin:lmadmin /opt/local/FNPLicenseServerManager/
sudo chmod +x /opt/local/FNPLicenseServerManager/lib*
sudo cp /opt/local/FNPLicenseServerManager/lib* /usr/lib/
echo "======================"
echo "Opening firewall ports"
echo "======================"
FWZONE=$(sudo firewall-cmd --list-all | grep "(active)" | tail -1 | cut -f 1 -d " ")
cat <<EOF | sudo tee /etc/firewalld/services/lmadmin.xml
<?xml version="1.0" encoding="utf-8"?>
<service version="1.0">
    <short>lmadmin</short>
    <description>lmadmin</description>
    <port port="8090" protocol="tcp"/>
    <port port="1101" protocol="tcp"/>
</service>
EOF
sleep 5
sudo firewall-cmd --zone=public --remove-port=8090/tcp --permanent
sudo firewall-cmd --zone=public --remove-port=1101/tcp --permanent
sudo firewall-cmd --zone=public --remove-port=27000-27009/tcp --permanent
sudo firewall-cmd --zone=internal --remove-port=8090/tcp --permanent
sudo firewall-cmd --zone=internal --remove-port=1101/tcp --permanent
sudo firewall-cmd --zone=internal --remove-port=27000-27009/tcp --permanent
sudo firewall-cmd --zone=$FWZONE --add-service=lmadmin --permanent
sudo firewall-cmd --reload
IP_ADDRESS=$(ip route get 1 | awk '{print $NF;exit}')
HOSTNAME=$(hostname)
echo "$IP_ADDRESS     $HOSTNAME" >> /etc/hosts 
echo "=========================================="
echo "Creating systemd service - lmadmin"
echo "=========================================="
sudo echo "[Unit]" > /etc/systemd/system/lmadmin.service
sudo echo "Description=Flexnet License Daemon" >> /etc/systemd/system/lmadmin.service
sudo echo "After=network.target network.service" >> /etc/systemd/system/lmadmin.service
sudo echo "" >> /etc/systemd/system/lmadmin.service
sudo echo "[Service]" >> /etc/systemd/system/lmadmin.service
sudo echo "User=lmadmin" >> /etc/systemd/system/lmadmin.service
sudo echo "WorkingDirectory=/opt/local/FNPLicenseServerManager/" >> /etc/systemd/system/lmadmin.service
sudo echo "ExecStart=/opt/local/FNPLicenseServerManager/lmadmin -allowStopServer yes" >> /etc/systemd/system/lmadmin.service
sudo echo "Restart=always" >> /etc/systemd/system/lmadmin.service
sudo echo "RestartSec=30" >> /etc/systemd/system/lmadmin.service
sudo echo "Type=forking" >> /etc/systemd/system/lmadmin.service
sudo echo "" >> /etc/systemd/system/lmadmin.service
sudo echo "[Install]" >> /etc/systemd/system/lmadmin.service
sudo echo "WantedBy=multi-user.target" >> /etc/systemd/system/lmadmin.service
sudo echo "" >> /etc/systemd/system/lmadmin.service
sudo chown root:root /etc/systemd/system/lmadmin.service
sudo chmod 755 /etc/systemd/system/lmadmin.service
sudo systemctl daemon-reload
sudo systemctl enable lmadmin.service
echo "=========================================="
echo "lmadmin service installation complete"
echo "  usage: systemctl start|stop lmadmin"
echo "=========================================="