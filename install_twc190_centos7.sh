#!/bin/bash
echo "=========================================="
echo "Installing Teamwork Cloud 19.0"
echo "=========================================="
echo "Installing unzip"
sudo yum install -y unzip
echo "Creating twcloud group and user"
sudo getent group twcloud >/dev/null || groupadd -r twcloud
sudo getent passwd twcloud >/dev/null || useradd -d /home/twcloud -g twcloud -m -r twcloud
echo ""
echo "IMPORTANT: Install into directory /opt/local/TeamworkCloud"
echo "           When prompted for user to run service, use twcloud"
read -p -"Press any key to continue ...: " -n1 -s
sudo wget http://download1.nomagic.com/twcloud190/twcloud_190_installer_linux64.bin
sudo chmod +x twcloud_190_installer_linux64.bin
sudo ./twcloud_190_installer_linux64.bin
sudo chown -R twcloud:twcloud /opt/local/TeamworkCloud/
IP_ADDRESS=$(ip route get 1 | awk '{print $NF;exit}')
sudo sed -i "s/\"localhost\"/\"$IP_ADDRESS\"/" /opt/local/TeamworkCloud/configuration/application.conf
sudo sed -i "s/localhost/$IP_ADDRESS/" /opt/local/TeamworkCloud/AuthServer/config/authserver.properties
echo "======================="
echo "Configuring firewall"
echo "======================="
FWZONE=$(sudo firewall-cmd --list-all | grep "(active)" | tail -1 | cut -f 1 -d " ")
echo "Discovered firewall zone $FWZONE"
cat <<EOF | sudo tee /etc/firewalld/services/twcloud.xml
<?xml version="1.0" encoding="utf-8"?>
<service version="1.0">
    <short>twcloud</short>
    <description>twcloud</description>
    <port port="8111" protocol="tcp"/>
    <port port="3579" protocol="tcp"/>
    <port port="8555" protocol="tcp"/>
    <port port="2552" protocol="tcp"/>
    <port port="2468" protocol="tcp"/>
</service>
EOF
sleep 5
sudo firewall-cmd --zone=$FWZONE --remove-port=8111/tcp --permanent
sudo firewall-cmd --zone=$FWZONE --remove-port=3579/tcp --permanent
sudo firewall-cmd --zone=$FWZONE --remove-port=8555/tcp --permanent
sudo firewall-cmd --zone=$FWZONE --remove-port=2552/tcp --permanent
sudo firewall-cmd --zone=$FWZONE --remove-port=2468/tcp --permanent
sudo firewall-cmd --zone=$FWZONE --add-service=twcloud --permanent
sudo firewall-cmd --reload