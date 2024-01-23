#!/bin/bash
################################
#   fixcassandraservice.sh
#
#   Fixes inability for systemd to control cassandra as a result of a vulnerability fix in systemd
#
################################
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

chkconfig --del cassandra
systemctl daemon-reload
systemctl enable cassandra

