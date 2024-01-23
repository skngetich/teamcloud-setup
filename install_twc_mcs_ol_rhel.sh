#!/bin/bash
NM_VERSION='2024x'
echo
if [ "$EUID" -ne 0 ];then
	echo "Please run as root or sudo."
	exit 1
fi
#Obtain OS information using either lsb_release or /etc/os-release
if ( type lsb_release &> /dev/null ); then
	OS=$(lsb_release -is)
	if [[ $OS =~ "RedHat" ]]; then OS="rhel"; fi
	if [[ $OS =~ "Oracle" ]]; then OS="ol"; fi
	OS_V=$(lsb_release -rs | cut -f1 -d.)
elif [ -f /etc/os-release ]; then
	source /etc/os-release
	OS=$ID
	OS_V=$(echo $VERSION_ID | cut -f1 -d.)
else
	echo "Installation Exited: Unable to obtain OS information."
	exit 1
fi
#Set package manager
if type -p dnf  > /dev/null; then
	PKG_EXE="dnf -y"
elif type -p yum > /dev/null; then
	PKG_EXE="yum -y"
else
	echo "Unable to find package manager (dnf or yum)."
fi

#Look for .bin installer file. Ask user to select one if multiple files are found.
BIN_FOUND=$(find *.bin | wc -l)
if [[ $BIN_FOUND == '1' ]]; then
	INSTALLER=$(find *.bin)
else
	echo
	echo "Multiple installer files found. Please select file for installation."
	BIN_FILES=($(ls *.bin))
	select file in "${BIN_FILES[@]}"; do
		if [[ -n $file ]]; then
			INSTALLER=$file
			break
		else
			echo "Invalid selection"
		fi
	done
fi
if [[ $INSTALLER =~ "magic" ]]; then
	PRODUCT="Magic Collaboration Studio ${NM_VERSION}"
elif [[ $INSTALLER =~ "twcloud" ]]; then
	PRODUCT="Teamwork Cloud ${NM_VERSION}"
else
	echo "Unrecognized installer file. Exiting."
	exit 1
fi

echo "======================================================"
echo "Installing $PRODUCT"
echo "======================================================"

#Determine OS and set install command for EPEL package
EPEL_RELEASE=$(rpm -qa | grep epel-release)
if [[ -n $EPEL_RELEASE ]]; then
	INSTALL_CMDS="echo Package $EPEL_RELEASE already installed, skipping."
else
	if [[ $OS  =~ "rhel" ]]; then
		echo "Installing epel-release for RHEL"
		INSTALL_CMDS="rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-$OS_V.noarch.rpm"
	elif [[ $OS  =~ "ol" ]]; then
		echo "Installing epel-release for Oracle Linux"
		INSTALL_CMDS="$PKG_EXE -q install epel-release"
	fi
fi
#Install EPEL Package
echo "Updating system packages ..."
eval $INSTALL_CMDS
$PKG_EXE -q update
echo "Installing unzip"
$PKG_EXE install unzip
echo "Installing fonts"
$PKG_EXE install dejavu-serif-fonts
echo "Installing Tomcat Native Libraries"
if [[ $OS  =~ "rhel" ]]; then
	$PKG_EXE --enablerepo=epel install tomcat-native
else
	$PKG_EXE install tomcat-native
fi
#echo "Creating twcloud group and user"
#getent group twcloud >/dev/null || groupadd -r twcloud
#getent passwd twcloud >/dev/null || useradd -d /home/twcloud -g twcloud -m -r twcloud
echo "Creating temporary directory for install anywhere"
IATEMPDIR=$(pwd)/_tmp
export IATEMPDIR
mkdir $IATEMPDIR
echo ""
echo "IMPORTANT: "
echo "           When prompted for user to run service, use twcloud"
echo "           When prompted for Java Home location, use Java 17 location, e.g., /etc/alternatives/jre_17"
echo ""
read -p -"Press any key to continue ...: " -n1 -s
echo
echo "Main installer starting ..."
chmod +x $INSTALLER
./$INSTALLER

FWSTATUS="$(systemctl is-active firewalld.service)"
if [ "${FWSTATUS}" = "active" ]; then
echo "======================="
echo "Configuring firewall"
echo "======================="
FWZONE=$(firewall-cmd --get-default-zone)
echo "Discovered firewall zone $FWZONE"
cat <<EOF > /etc/firewalld/services/twcloud.xml
<?xml version="1.0" encoding="utf-8"?>
<service version="1.0">
    <short>twcloud</short>
    <description>twcloud</description>
    <port port="8111" protocol="tcp"/>
    <port port="3579" protocol="tcp"/>
    <port port="10002" protocol="tcp"/>
    <port port="2552" protocol="tcp"/>
    <port port="2468" protocol="tcp"/>
    <port port="8443" protocol="tcp"/>
</service>
EOF
sleep 10
firewall-cmd --zone=$FWZONE --remove-port=8111/tcp --permanent &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=3579/tcp --permanent &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=8555/tcp --permanent &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=2552/tcp --permanent &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=2468/tcp --permanent &> /dev/null
firewall-cmd --zone=$FWZONE --add-service=twcloud --permanent
firewall-cmd --reload
else
echo "======================="
echo "Firewall is not running - skipping firewall configuration"
echo "======================="
fi

echo "Increase file limits for twcloud user"
echo "twcloud - nofile 50000" > /etc/security/limits.d/twcloud.conf

#Check if tuning was applied from previous installation. Skip if applied from before.
if ! ( grep -q "tunings for Teamwork Cloud" /etc/sysctl.conf ); then
echo "Applying post-install performance tuning"
echo "  /etc/sysctl.conf tuning"
cat <<EOF >> /etc/sysctl.conf
 
#  Preliminary tunings for Teamwork Cloud
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.optmem_max=40960
net.core.default_qdisc=fq
net.core.somaxconn=4096
net.ipv4.conf.all.arp_notify = 1
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_rmem=4096 12582912 16777216
net.ipv4.tcp_wmem=4096 12582912 16777216
net.ipv4.tcp_max_syn_backlog=8096
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
vm.max_map_count = 1048575
vm.swappiness = 0
vm.dirty_background_ratio=5
vm.dirty_ratio=80
vm.dirty_expire_centisecs = 12000
EOF
sleep 10
sysctl -p
else
echo "Skipping post-install performance tuning. Already configured."
fi

# Configure tunedisk config to run during boot. Only configures if TWCLOUD_HOME is found.
TWC_ENV_PATH=/etc/twcloud/twcloud-env
if [ -f $TWC_ENV_PATH ]; then
	source $TWC_ENV_PATH
	TWC_TUNE_PATH=$TWCLOUD_HOME/scripts/linux
	echo "  ... Creating disk, CPU, and memory tuning parameters in:"
	echo "        $TWC_TUNE_PATH/tunedisk.sh"

cat << EOF > $TWC_TUNE_PATH/tunedisk.sh
#!/bin/bash
## Added for disk tuning this read-heavy interactive system
sleep 10
#for DISK in sda sdb sdc sdd
for DISK in \$(ls -all /sys/block | egrep 'sd|xvd' | awk '{for(i=1;i<=NF;i++){if(\$i == "->"){print \$(i-1) OFS}}}')
do
    echo \$DISK
    # Select none scheduler first
    echo none > /sys/block/\${DISK}/queue/scheduler
    echo scheduler: \$(cat /sys/block/\${DISK}/queue/scheduler)
    echo 1 > /sys/block/\${DISK}/queue/nomerges
    echo nomerges: \$(cat /sys/block/\${DISK}/queue/nomerges)
    echo 256 > /sys/block/\${DISK}/queue/read_ahead_kb
    echo read_ahead_kb: \$(cat /sys/block/\${DISK}/queue/read_ahead_kb)
    echo 0 > /sys/block/\${DISK}/queue/rotational
    echo rotational: \$(cat /sys/block/\${DISK}/queue/rotational)
    echo 256 > /sys/block/\${DISK}/queue/nr_requests
    echo nr_requests: \$(cat /sys/block/\${DISK}/queue/nr_requests)
     
    echo 2 > /sys/block/\${DISK}/queue/rq_affinity
    echo rq_affinity: \$(cat /sys/block/\${DISK}/queue/rq_affinity)
done
# Disable huge page defrag
echo never | tee /sys/kernel/mm/transparent_hugepage/defrag
 
#Disable CPU Freq scaling
 
for CPUFREQ in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
do
    [ -f \$CPUFREQ ] || continue
    echo -n performance > \$CPUFREQ
done
 
#Disable zone-reclaim
 
echo 0 > /proc/sys/vm/zone_reclaim_mode
EOF
sleep 10
chmod +x $TWC_TUNE_PATH/tunedisk.sh
echo "  ... Setting parameters to be executed on server restart"
# Check if rc.local was set to run tunedisk.sh from previous installation.
# Replace tunedisk.sh path if found. Ignore if tunedisk was set previously.
if ( grep -q "/home/twcloud/tunedisk.sh" /etc/rc.local ); then
	sed -i "s+/home/twcloud/tunedisk.sh.*+$TWC_TUNE_PATH/tunedisk.sh+g" /etc/rc.local
fi
if ! ( grep -q "tuning for TeamworkCloud" /etc/rc.local ); then
cat <<EOF >> /etc/rc.local
 
#  Perform additional tuning for TeamworkCloud
$TWC_TUNE_PATH/tunedisk.sh
EOF
chmod +x /etc/rc.d/rc.local
fi

echo "  ... Applying tuning changes - there is a 30 second delay before execution"
$TWC_TUNE_PATH/tunedisk.sh
fi  # TWC_ENV_PATH check close

echo "Removing installanywhere temporary directory"
rm -fr $IATEMPDIR

# Archive initial set of configuration files and self-signed keystore from installation
TWC_BACKUP_UTIL=${TWCLOUD_HOME%/*}/Utilities/AdminTools/backup-twc-configs.sh
if [ -f $TWC_BACKUP_UTIL ]; then $TWC_BACKUP_UTIL; fi

echo "Post-install configuration completed."
echo