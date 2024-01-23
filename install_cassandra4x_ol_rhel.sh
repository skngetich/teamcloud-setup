#!/bin/bash
CASSANDRA_VER=4.1.3

# Package Downloads
CASSANDRA_JAVA_PKG=java-11-openjdk  #Default Java required by Cassandra
CASSANDRA_JAVA17_PKG=java-17-openjdk  #Installs tzdata needed by Cassandra 4.1
CASSANDRA_PKG_URL=https://apache.jfrog.io/artifactory/cassandra-rpm/41x/cassandra-$CASSANDRA_VER-1.noarch.rpm
CASSANDRA_TOOLS_URL=https://apache.jfrog.io/artifactory/cassandra-rpm/41x/cassandra-tools-$CASSANDRA_VER-1.noarch.rpm
# EPEL Fedora RPM for RHEL Systems (version 8 is default, URL updates once OS info is obtained)
EPEL_PKG_URL=https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
# Only use this package if installing from EPEL Repository is not possible.
JEMALLOC_PKG_URL=https://repo.percona.com/yum/release/8/RPMS/x86_64/jemalloc-3.6.0-1.el8.x86_64.rpm
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
	echo "Defaulting to manual jemalloc installation, instead of pulling from EPEL repository."
	INSTALL_CMDS="rpm -ivh $JEMALLOC_PKG_URL"
fi

echo "========================================================"
echo "Installing Apache Cassandra $CASSANDRA_VER for $OS $OS_V"
echo "========================================================"
echo "Removing Datastax Community Edition"
$PKG_EXE remove datastax-agent  &> /dev/null
$PKG_EXE remove opscenter  &> /dev/null
rm -f /etc/yum.repos.d/datastax.repo  &> /dev/null
echo "Removing old Cassandra repos"
rm -f /etc/yum.repos.d/cassandra.repo &> /dev/null

#Install Java for Cassandra and set installed version as default system Java.
$PKG_EXE install $CASSANDRA_JAVA_PKG
echo "========================================"
echo "Setting Java 11 as default on the system"
echo "========================================"
alternatives --set java $(grep "java-11" /var/lib/alternatives/java | grep -o -P '(?<=@).*(?=@)')

#Install Cassandra 4 from downloaded RPM packages
$PKG_EXE install $CASSANDRA_PKG_URL
$PKG_EXE install $CASSANDRA_TOOLS_URL

#Determine which OS then set the proper install commands for jemalloc
if [[ $OS  =~ "rhel" ]]; then
	echo "Installing packages epel-release and jemalloc for RHEL $OS_V"
	EPEL_PKG_URL=https://dl.fedoraproject.org/pub/epel/epel-release-latest-$OS_V.noarch.rpm
	INSTALL_CMDS="$PKG_EXE -q install $EPEL_PKG_URL && $PKG_EXE -q update && $PKG_EXE --enablerepo=epel install jemalloc"
elif [[ $OS  =~ "ol" ]]; then
	#Oracle 8 EPEL from repo and jemalloc install comannds
	echo "Installing packages epel-release and jemalloc for Oracle Linux $OS_V"
	INSTALL_CMDS="$PKG_EXE -q install epel-release && $PKG_EXE -q update && $PKG_EXE install jemalloc"
fi
#Install jemalloc based on OS detected
eval $INSTALL_CMDS
#Install Java 17
$PKG_EXE install $CASSANDRA_JAVA17_PKG

FWSTATUS="$(systemctl is-active firewalld.service)"
if [ "${FWSTATUS}" = "active" ]; then
echo "======================="
echo "Configuring firewall"
echo "======================="
FWZONE=$(firewall-cmd --get-default-zone)
echo "Discovered firewall zone $FWZONE"
cat <<EOF > /etc/firewalld/services/cassandra.xml
<?xml version="1.0" encoding="utf-8"?>
<service version="1.0">
    <short>cassandra</short>
    <description>cassandra</description>
    <port port="7000" protocol="tcp"/>
    <port port="7001" protocol="tcp"/>
    <port port="9042" protocol="tcp"/>
    <port port="9142" protocol="tcp"/>
</service>
EOF
sleep 10
firewall-cmd --zone=$FWZONE --remove-port=7000/tcp --permanent  &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=7001/tcp --permanent  &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=7199/tcp --permanent  &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=9042/tcp --permanent  &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=9142/tcp --permanent  &> /dev/null
firewall-cmd --zone=$FWZONE --remove-port=9160/tcp --permanent  &> /dev/null
firewall-cmd --zone=$FWZONE --add-service=cassandra --permanent
firewall-cmd --reload
else
echo "======================="
echo "Firewall is not running - skipping firewall configuration"
echo "======================="
fi
echo "====================================================="
echo "Changing ownership of data and commit log directories"
echo "====================================================="
mkdir /data &> /dev/null
mkdir /logs &> /dev/null
chown cassandra:cassandra /data &> /dev/null
chown cassandra:cassandra /logs &> /dev/null
echo "====================================================="
echo "Making configuration file changes"
echo "====================================================="
IP_ADDRESS=$(ip route get 1 | sed 's/^.*src \([^ ]*\).*$/\1/;q')
HOSTNAME=$(hostname)
cp /etc/cassandra/default.conf/cassandra.yaml /etc/cassandra/default.conf/cassandra.yaml.backup
cp /etc/cassandra/default.conf/cassandra.yaml ./cassandra.yaml.template
sed -i "s/- seeds: \"127.0.0.1/- seeds: \"$IP_ADDRESS/g" cassandra.yaml.template
sed -i "s/listen_address:.*/listen_address: $IP_ADDRESS/g" cassandra.yaml.template
sed -i "s/# broadcast_rpc_address:.*/broadcast_rpc_address: $IP_ADDRESS/g" cassandra.yaml.template
sed -i "s/broadcast_rpc_address:.*/broadcast_rpc_address: $IP_ADDRESS/g" cassandra.yaml.template
sed -i "s/# commitlog_total_space:.*/commitlog_total_space: 8192MiB/g" cassandra.yaml.template
sed -i "s/commitlog_total_space:.*/commitlog_total_space: 8192MiB/g" cassandra.yaml.template
sed -i "s/^rpc_address:.*/rpc_address: 0.0.0.0/g" cassandra.yaml.template
sed -i "s/commitlog_segment_size:.*/commitlog_segment_size: 192MiB/g" cassandra.yaml.template
sed -i "s/read_request_timeout:.*/read_request_timeout: 1800000ms/g" cassandra.yaml.template
sed -i "s/range_request_timeout:.*/range_request_timeout: 1800000ms/g" cassandra.yaml.template
sed -i "s/^write_request_timeout:.*/write_request_timeout: 1800000ms/g" cassandra.yaml.template
sed -i "s/cas_contention_timeout:.*/cas_contention_timeout: 1000ms/g" cassandra.yaml.template
sed -i "s/truncate_request_timeout:.*/truncate_request_timeout: 1800000ms/g" cassandra.yaml.template
sed -i "s/request_timeout:.*/request_timeout: 1800000ms/g" cassandra.yaml.template
sed -i "s/batch_size_warn_threshold:.*/batch_size_warn_threshold: 3000KiB/g" cassandra.yaml.template
sed -i "s/batch_size_fail_threshold:.*/batch_size_fail_threshold: 5000KiB/g" cassandra.yaml.template
sed -i '/data_file_directories:.*/!b;n;c\ \ \ \ - \/data\/data' cassandra.yaml.template
sed -i "s/hints_directory:.*/hints_directory: \/data\/hints/g" cassandra.yaml.template
sed -i "s/commitlog_directory:.*/commitlog_directory: \/logs\/commitlog/g" cassandra.yaml.template
sed -i "s/saved_caches_directory:.*/saved_caches_directory: \/data\/saved_caches/g" cassandra.yaml.template
cp -fR ./cassandra.yaml.template /etc/cassandra/default.conf/cassandra.yaml
#Obtain server CPU count
NPROCS=$(nproc)
#Modify jvm11-server.options for Cassandra 4
cp /etc/cassandra/default.conf/jvm11-server.options /etc/cassandra/default.conf/jvm11-server.options.backup
cp /etc/cassandra/default.conf/jvm11-server.options ./jvm11-server.options.template
sed -i "s/-XX:+UseConcMarkSweepGC/#-XX:+UseConcMarkSweepGC/g" jvm11-server.options.template
sed -i "s/-XX:+CMSParallelRemarkEnabled/#-XX:+CMSParallelRemarkEnabled/g" jvm11-server.options.template
sed -i "s/-XX:SurvivorRatio=8/#-XX:SurvivorRatio=8/g" jvm11-server.options.template
sed -i "s/-XX:MaxTenuringThreshold=1/#-XX:MaxTenuringThreshold=1/g" jvm11-server.options.template
sed -i "s/-XX:CMSInitiatingOccupancyFraction=75/#-XX:CMSInitiatingOccupancyFraction=75/g" jvm11-server.options.template
sed -i "s/-XX:+UseCMSInitiatingOccupancyOnly/#-XX:+UseCMSInitiatingOccupancyOnly/g" jvm11-server.options.template
sed -i "s/-XX:CMSWaitDuration=10000/#-XX:CMSWaitDuration=10000/g" jvm11-server.options.template
sed -i "s/-XX:+CMSParallelInitialMarkEnabled/#-XX:+CMSParallelInitialMarkEnabled/g" jvm11-server.options.template
sed -i "s/-XX:+CMSEdenChunksRecordAlways/#-XX:+CMSEdenChunksRecordAlways/g" jvm11-server.options.template
sed -i "s/-XX:+CMSClassUnloadingEnabled/#-XX:+CMSClassUnloadingEnabled/g" jvm11-server.options.template
sed -i "s/#-XX:+UseG1GC/-XX:+UseG1GC/g" jvm11-server.options.template
sed -i "s/#-XX:MaxGCPauseMillis=300/-XX:MaxGCPauseMillis=300/g" jvm11-server.options.template
sed -i "s/#-XX:ParallelGCThreads=16/-XX:ParallelGCThreads=$NPROCS/g" jvm11-server.options.template
sed -i "s/#-XX:ConcGCThreads=16/-XX:ConcGCThreads=$NPROCS/g" jvm11-server.options.template
cp -fR ./jvm11-server.options.template /etc/cassandra/default.conf/jvm11-server.options
#Modify jvm8-server.options for Cassandra 4
cp /etc/cassandra/default.conf/jvm8-server.options /etc/cassandra/default.conf/jvm8-server.options.backup
cp /etc/cassandra/default.conf/jvm8-server.options ./jvm8-server.options.template
sed -i "s/-XX:+UseParNewGC/#-XX:+UseParNewGC/g" jvm8-server.options.template
sed -i "s/-XX:+UseConcMarkSweepGC/#-XX:+UseConcMarkSweepGC/g" jvm8-server.options.template
sed -i "s/-XX:+CMSParallelRemarkEnabled/#-XX:+CMSParallelRemarkEnabled/g" jvm8-server.options.template
sed -i "s/-XX:SurvivorRatio=8/#-XX:SurvivorRatio=8/g" jvm8-server.options.template
sed -i "s/-XX:MaxTenuringThreshold=1/#-XX:MaxTenuringThreshold=1/g" jvm8-server.options.template
sed -i "s/-XX:CMSInitiatingOccupancyFraction=75/#-XX:CMSInitiatingOccupancyFraction=75/g" jvm8-server.options.template
sed -i "s/-XX:+UseCMSInitiatingOccupancyOnly/#-XX:+UseCMSInitiatingOccupancyOnly/g" jvm8-server.options.template
sed -i "s/-XX:CMSWaitDuration=10000/#-XX:CMSWaitDuration=10000/g" jvm8-server.options.template
sed -i "s/-XX:+CMSParallelInitialMarkEnabled/#-XX:+CMSParallelInitialMarkEnabled/g" jvm8-server.options.template
sed -i "s/-XX:+CMSEdenChunksRecordAlways/#-XX:+CMSEdenChunksRecordAlways/g" jvm8-server.options.template
sed -i "s/-XX:+CMSClassUnloadingEnabled/#-XX:+CMSClassUnloadingEnabled/g" jvm8-server.options.template
sed -i "s/#-XX:+UseG1GC/-XX:+UseG1GC/g" jvm8-server.options.template
sed -i "s/#-XX:MaxGCPauseMillis=300/-XX:MaxGCPauseMillis=300/g" jvm8-server.options.template
sed -i "s/#-XX:ParallelGCThreads=16/-XX:ParallelGCThreads=$NPROCS/g" jvm8-server.options.template
sed -i "s/#-XX:ConcGCThreads=16/-XX:ConcGCThreads=$NPROCS/g" jvm8-server.options.template
sed -i "s/-XX:+PrintGCDetails/#-XX:+PrintGCDetails/g" jvm8-server.options.template
sed -i "s/-XX:+PrintGCDateStamps/#-XX:+PrintGCDateStamps/g" jvm8-server.options.template
sed -i "s/-XX:+PrintHeapAtGC/#-XX:+PrintHeapAtGC/g" jvm8-server.options.template
sed -i "s/-XX:+PrintTenuringDistribution/#-XX:+PrintTenuringDistribution/g" jvm8-server.options.template
sed -i "s/-XX:+PrintGCApplicationStoppedTime/#-XX:+PrintGCApplicationStoppedTime/g" jvm8-server.options.template
sed -i "s/-XX:+PrintPromotionFailure/#-XX:+PrintPromotionFailure/g" jvm8-server.options.template
sed -i "s/-XX:+UseGCLogFileRotation/#-XX:+UseGCLogFileRotation/g" jvm8-server.options.template
sed -i "s/-XX:NumberOfGCLogFiles=10/#-XX:NumberOfGCLogFiles=10/g" jvm8-server.options.template
sed -i "s/-XX:GCLogFileSize=10M/#-XX:GCLogFileSize=10M/g" jvm8-server.options.template
cp -fR ./jvm8-server.options.template /etc/cassandra/default.conf/jvm8-server.options
#Modify logback.xml
cp /etc/cassandra/default.conf/logback.xml /etc/cassandra/default.conf/logback.xml.backup
cp /etc/cassandra/default.conf/logback.xml ./logback.xml.template
sed -i 's|<appender-ref ref="ASYNCDEBUGLOG" />|<!-- <appender-ref ref="ASYNCDEBUGLOG" /> -->|g' logback.xml.template
cp -fR logback.xml.template /etc/cassandra/default.conf/logback.xml

# Apply fix to systemd vulnerability preventing service control of cassandra
cat << EOF > /etc/systemd/system/cassandra.service
[Unit]
Description=Apache Cassandra
After=network.target

[Service]
PIDFile=/var/run/cassandra/cassandra.pid
User=cassandra
Group=cassandra
ExecStart=/usr/sbin/cassandra -f -p /var/run/cassandra/cassandra.pid
Restart=always
LimitNOFILE=100000
LimitMEMLOCK=infinity
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF
sleep 10
chkconfig --del cassandra
systemctl daemon-reload
systemctl enable cassandra
echo
echo "Cassandra installation completed."
echo

