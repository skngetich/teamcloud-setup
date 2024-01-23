#!/bin/bash
FN_INSTALL_PATH=/opt/local/FNPLicenseServerManager
CAMEO_URL=https://d1g91r27pzl568.cloudfront.net/Cameo_daemon/FlexNet_11_19/linux64/cameo.zip
LMGRD_URL=https://d1oqhepk9od1tu.cloudfront.net/Flex_License_Server_Utilities/v11.19.0/linux64/lmgrd.zip
LMADMIN_URL=https://d1oqhepk9od1tu.cloudfront.net/Flex_License_Server_Utilities/v11.19.0/linux64/lmadmin-x64_lsb-11_19_0_0.bin
echo "============================="
echo "Installing Auxiliary Packages"
echo "============================="
yum install -y wget
yum install -y unzip
yum install -y java-11-openjdk
yum install -y ld-linux.so.2
bash -c "if [ ! -e /lib64/ld-lsb-x86-64.so.3 ]; then ln -s ld-linux-x86-64.so.2 /lib64/ld-lsb-x86-64.so.3; fi"

echo "=================="
echo "Installing lmadmin"
echo "=================="
echo "Creating temporary directory for install anywhere"
IATEMPDIR=$(pwd)/_tmp
export IAEMPDIR
mkdir $IATEMPDIR
getent group lmadmin >/dev/null || groupadd -r lmadmin
getent passwd lmadmin >/dev/null || useradd -g lmadmin -r lmadmin
echo "lmadmin ALL=(ALL) NOPASSWD:ALL " >> /etc/sudoers
# If Web GUI to Flex licensing is not a must - lmgrd can be used, can be placed in rc.local to startup on boot
# usage - ./lmgrd -c PATH_TO_KEY_FILE -l PATH_TO_LOG_FILE
# RW rights needed to both files
echo "==========================================================="
echo "Getting Linux 64-bit IPv6 version 11.19 "
echo "==========================================================="
wget $CAMEO_URL
unzip cameo.zip
chmod +x cameo
echo "========================================"
echo "Getting Linux 64-bit lmgrd version 11.19"
echo "========================================"
wget $LMGRD_URL
unzip lmgrd.zip
chmod +x lmgrd
echo "======================================"
echo "Making flex log file named FlexLog.log"
echo "======================================"
touch FlexLog.log
chmod 664 FlexLog.log
echo "=========================================="
echo "Getting Linux 64-bit lmadmin version 11.19"
echo "=========================================="
wget $LMADMIN_URL
INSTALLER=$(find lmadmin*.bin)
echo "Installer file: $INSTALLER"
chmod +x $INSTALLER
echo "========================================="
echo "Executing lmadmin version 11.19 installer"
echo "IMPORTANT: Install into directory $FN_INSTALL_PATH"
echo ""
echo " Note:  Accept all defaults for script to work properly!!!"
echo ""
read -p -"Press any key to continue ...: " -n1 -s
echo "=========================================="
JAVA_TOOL_OPTIONS="-Djdk.util.zip.disableZip64ExtraFieldValidation=true" ./$INSTALLER -i console -DUSER_INSTALL_DIR=$FN_INSTALL_PATH
mkdir -p $FN_INSTALL_PATH/licenses/cameo/
cp cameo $FN_INSTALL_PATH/cameo
mv cameo $FN_INSTALL_PATH/licenses/cameo/cameo
mv lmgrd $FN_INSTALL_PATH/lmgrd
mv FlexLog.log $FN_INSTALL_PATH/FlexLog.log
chown -R lmadmin:lmadmin $FN_INSTALL_PATH/

FWSTATUS="$(systemctl is-active firewalld.service)"
if [ "${FWSTATUS}" = "active" ]; then
echo "======================="
echo "Configuring firewall"
echo "======================="
FWZONE=$(firewall-cmd --get-default-zone)
cat <<EOF > /etc/firewalld/services/lmadmin.xml
<?xml version="1.0" encoding="utf-8"?>
<service version="1.0">
    <short>lmadmin</short>
    <description>lmadmin</description>
    <port port="8090" protocol="tcp"/>
    <port port="1101" protocol="tcp"/>
</service>
EOF
sleep 10
firewall-cmd --zone=public --remove-port=8090/tcp --permanent &> /dev/null 
firewall-cmd --zone=public --remove-port=1101/tcp --permanent &> /dev/null 
firewall-cmd --zone=public --remove-port=27000-27009/tcp --permanent &> /dev/null 
firewall-cmd --zone=internal --remove-port=8090/tcp --permanent &> /dev/null 
firewall-cmd --zone=internal --remove-port=1101/tcp --permanent &> /dev/null 
firewall-cmd --zone=internal --remove-port=27000-27009/tcp --permanent &> /dev/null 
firewall-cmd --zone=$FWZONE --add-service=lmadmin --permanent
firewall-cmd --reload
else
echo "========================================================="
echo "Firewall is not running - skipping firewall configuration"
echo "========================================================="
fi

# If IP and host are not resolved properly, uncomment the next 3 lines to associate IP with host.
#IP_ADDRESS=$(ip route get 1 | sed 's/^.*src \([^ ]*\).*$/\1/;q')
#HOSTNAME=$(hostname)
#echo "$IP_ADDRESS     $HOSTNAME" >> /etc/hosts  
echo "=========================================="
echo "Creating systemd service - lmadmin"
echo "=========================================="
cat <<EOF > /etc/systemd/system/lmadmin.service
[Unit]
Description=Flexnet License Daemon
After=network.target network.service

[Service]
User=lmadmin
WorkingDirectory=$FN_INSTALL_PATH/
ExecStart=$FN_INSTALL_PATH/lmadmin -allowStopServer yes
Restart=always
RestartSec=30
Type=forking

[Install]
WantedBy=multi-user.target

EOF
chown root:root /etc/systemd/system/lmadmin.service
chmod 755 /etc/systemd/system/lmadmin.service
systemctl daemon-reload
systemctl enable lmadmin.service
echo "Removing installanywhere temporary directory"
rm -fr $IATEMPDIR
echo "=========================================="
echo "lmadmin service installation complete"
echo "  usage: systemctl start|stop lmadmin"
echo "=========================================="
